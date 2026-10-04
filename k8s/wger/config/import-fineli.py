"""One-off, English-only Fineli importer for wger 2.6.

Run through ``manage.py shell`` inside the wger web container. The script defaults to a
read-only dry run. Runtime controls are environment variables because Django's shell command
does not forward custom command-line arguments:

    FINELI_DRY_RUN=true|false  (default: true)
    FINELI_LIMIT=100           (default: all valid foods)
    FINELI_FOOD_IDS=11060,812  (default: all foods)

This is a deployment-local importer, not a reusable upstream management command. The suspended
Kubernetes CronJob is only a template; an operator must explicitly create a one-off Job from it.
"""

import csv
import hashlib
import io
import os
import uuid
import zipfile
from collections import defaultdict
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP

import requests


FINELI_ZIP_URL = "https://fineli.fi/fineli/content/file/47"
FINELI_KJ_PER_KCAL = Decimal("4.1858")
LANGUAGE_CODE = "en"
SOURCE_NAME = "Fineli"
ATTRIBUTION = "Terveyden ja hyvinvoinnin laitos (THL), Fineli"
ATTRIBUTION_URL = "https://fineli.fi/"
SKIP_UNIT_CODES = {"G", "PORT1000KJ"}
REQUIRED_COMPONENTS = {"ENERC", "FAT", "CHOAVL", "PROT"}
OPTIONAL_COMPONENTS = {"SUGAR", "FASAT", "FIBC", "NA"}
MAX_DOWNLOAD_BYTES = 10 * 1024 * 1024
MAX_UNCOMPRESSED_BYTES = 25 * 1024 * 1024


def env_bool(name, default):
    value = os.environ.get(name)
    if value is None:
        return default
    normalized = value.strip().lower()
    if normalized in {"1", "true", "yes", "on"}:
        return True
    if normalized in {"0", "false", "no", "off"}:
        return False
    raise ValueError(f"{name} must be true or false")


def env_limit():
    raw = os.environ.get("FINELI_LIMIT", "").strip()
    if not raw:
        return None
    value = int(raw)
    if value < 1:
        raise ValueError("FINELI_LIMIT must be a positive integer")
    return value


def env_food_ids():
    raw = os.environ.get("FINELI_FOOD_IDS", "").strip()
    if not raw:
        return None
    return {part.strip() for part in raw.split(",") if part.strip()}


def download_archive():
    print(f"Downloading {FINELI_ZIP_URL}")
    response = requests.get(
        FINELI_ZIP_URL,
        headers={
            "User-Agent": "wger-fineli-import/0.1",
            "Accept": "application/zip,*/*;q=0.8",
        },
        timeout=(10, 60),
    )
    response.raise_for_status()
    payload = response.content
    if len(payload) > MAX_DOWNLOAD_BYTES:
        raise RuntimeError(f"Fineli archive unexpectedly large: {len(payload)} bytes")
    digest = hashlib.sha256(payload).hexdigest()
    print(f"Downloaded {len(payload)} bytes (sha256={digest})")

    archive = zipfile.ZipFile(io.BytesIO(payload))
    expanded_size = sum(member.file_size for member in archive.infolist())
    if expanded_size > MAX_UNCOMPRESSED_BYTES:
        raise RuntimeError(
            f"Fineli archive expands to an unexpected {expanded_size} bytes"
        )
    return archive


def read_csv(archive, name):
    try:
        payload = archive.read(name)
    except KeyError as exc:
        raise RuntimeError(f"Fineli archive is missing {name}") from exc
    text = payload.decode("cp1252")
    return list(csv.DictReader(io.StringIO(text), delimiter=";"))


def parse_decimal(value):
    try:
        return Decimal(value.replace(",", "."))
    except (AttributeError, InvalidOperation) as exc:
        raise ValueError(f"Invalid Fineli decimal: {value!r}") from exc


def quantize_macro(value):
    if value is None:
        return None
    return value.quantize(Decimal("0.001"), rounding=ROUND_HALF_UP)


def normalize_name(value):
    # The bulk package stores localized names in uppercase. Fineli's JSON API presents the same
    # names in title case, so mirror that display convention for the local wger catalog.
    return value.strip().title()


def ingredient_uuid(food_id):
    return uuid.uuid5(
        uuid.NAMESPACE_URL, f"https://fineli.fi/food/{food_id}?language=en"
    )


def unit_uuid(food_id, unit_code):
    return uuid.uuid5(
        uuid.NAMESPACE_URL,
        f"https://fineli.fi/food/{food_id}/unit/{unit_code}?language=en",
    )


def validate_nutrition(food_id, values):
    missing = sorted(REQUIRED_COMPONENTS - values.keys())
    if missing:
        return f"missing required components: {', '.join(missing)}"

    protein = values["PROT"]
    carbohydrates = values["CHOAVL"]
    fat = values["FAT"]
    sugar = values.get("SUGAR")
    saturated = values.get("FASAT")
    fiber = values.get("FIBC")
    sodium = values.get("NA", Decimal(0)) / 1000

    macros = {
        "protein": protein,
        "carbohydrates": carbohydrates,
        "fat": fat,
        "carbohydrates_sugar": sugar,
        "fat_saturated": saturated,
        "fiber": fiber,
        "sodium": sodium,
    }
    for field, value in macros.items():
        if value is not None and not Decimal(0) <= value <= Decimal(100):
            return f"{field} is outside 0..100: {value}"
    if protein + carbohydrates + fat > 100:
        return f"protein + carbohydrates + fat exceeds 100: {protein + carbohydrates + fat}"
    if sugar is not None and sugar > carbohydrates:
        return f"sugar exceeds carbohydrates: {sugar} > {carbohydrates}"
    if saturated is not None and saturated > fat:
        return f"saturated fat exceeds fat: {saturated} > {fat}"
    return None


def load_source_records(archive):
    foods = {row["FOODID"]: row for row in read_csv(archive, "food.csv")}
    names = {
        row["FOODID"]: row["FOODNAME"] for row in read_csv(archive, "foodname_EN.csv")
    }
    unit_names = {
        row["THSCODE"]: row["DESCRIPT"] for row in read_csv(archive, "foodunit_EN.csv")
    }

    values = defaultdict(dict)
    wanted_components = REQUIRED_COMPONENTS | OPTIONAL_COMPONENTS
    for row in read_csv(archive, "component_value.csv"):
        if row["EUFDNAME"] in wanted_components:
            values[row["FOODID"]][row["EUFDNAME"]] = parse_decimal(row["BESTLOC"])

    units = defaultdict(list)
    for row in read_csv(archive, "foodaddunit.csv"):
        units[row["FOODID"]].append(
            {
                "code": row["FOODUNIT"],
                "mass": parse_decimal(row["MASS"]),
            }
        )
    return foods, names, values, units, unit_names


def build_records(archive, requested_ids=None, limit=None):
    foods, names, values, units, unit_names = load_source_records(archive)
    source_ids = set(foods)
    if requested_ids is not None:
        missing_ids = sorted(requested_ids - source_ids, key=int)
        if missing_ids:
            raise ValueError(
                f"Requested Fineli IDs not found: {', '.join(missing_ids)}"
            )
        source_ids &= requested_ids

    records = []
    skipped = {}
    skipped_units = []

    for food_id in sorted(source_ids, key=int):
        nutrition = values.get(food_id, {})
        problem = validate_nutrition(food_id, nutrition)
        if problem:
            skipped[food_id] = problem
            continue
        if food_id not in names or not names[food_id].strip():
            skipped[food_id] = "missing English name"
            continue

        portion_records = []
        seen_portions = set()
        for source_unit in units.get(food_id, []):
            code = source_unit["code"]
            if code in SKIP_UNIT_CODES:
                continue
            name = unit_names.get(code, "").strip()
            grams = int(
                source_unit["mass"].quantize(Decimal("1"), rounding=ROUND_HALF_UP)
            )
            if not name or grams < 1:
                skipped_units.append((food_id, code, str(source_unit["mass"])))
                continue
            dedupe_key = (name.casefold(), grams)
            if dedupe_key in seen_portions:
                continue
            seen_portions.add(dedupe_key)
            portion_records.append(
                {
                    "uuid": unit_uuid(food_id, code),
                    "name": name,
                    "gram": grams,
                }
            )

        records.append(
            {
                "food_id": food_id,
                "uuid": ingredient_uuid(food_id),
                "name": normalize_name(names[food_id]),
                "energy": int(
                    (nutrition["ENERC"] / FINELI_KJ_PER_KCAL).quantize(
                        Decimal("1"), rounding=ROUND_HALF_UP
                    )
                ),
                "protein": quantize_macro(nutrition["PROT"]),
                "carbohydrates": quantize_macro(nutrition["CHOAVL"]),
                "carbohydrates_sugar": quantize_macro(nutrition.get("SUGAR")),
                "fat": quantize_macro(nutrition["FAT"]),
                "fat_saturated": quantize_macro(nutrition.get("FASAT")),
                "fiber": quantize_macro(nutrition.get("FIBC")),
                "sodium": quantize_macro(
                    nutrition["NA"] / 1000 if "NA" in nutrition else None
                ),
                "units": portion_records,
            }
        )

    if limit is not None:
        records = records[:limit]
    return records, skipped, skipped_units


def print_report(records, skipped, skipped_units, dry_run):
    print(f"Mode: {'DRY RUN' if dry_run else 'IMPORT'}")
    print(f"Prepared {len(records)} English ingredient records")
    print(f"Prepared {sum(len(record['units']) for record in records)} portion records")
    print(f"Skipped {len(skipped)} foods")
    for food_id, reason in sorted(skipped.items(), key=lambda item: int(item[0])):
        print(f"  skip food {food_id}: {reason}")
    print(f"Skipped {len(skipped_units)} unusable portion rows")
    print("Sample:")
    for record in records[:10]:
        print(
            f"  {record['food_id']}: {record['name']} — {record['energy']} kcal, "
            f"P {record['protein']} / C {record['carbohydrates']} / F {record['fat']}, "
            f"{len(record['units'])} portions"
        )


def import_records(records):
    from django.db import transaction
    from wger.core.models import Language, License
    from wger.nutrition.models import Ingredient, IngredientWeightUnit

    language = Language.objects.get(short_name=LANGUAGE_CODE)
    license_obj = License.objects.get(short_name="CC-BY 4")
    created_count = 0
    updated_count = 0
    unit_created_count = 0
    unit_updated_count = 0

    for index, record in enumerate(records, start=1):
        food_id = record["food_id"]
        object_url = f"https://fineli.fi/fineli/en/elintarvikkeet/{food_id}"
        source_url = f"https://fineli.fi/fineli/api/v1/foods/{food_id}"
        defaults = {
            "language": language,
            "name": record["name"],
            "energy": record["energy"],
            "protein": record["protein"],
            "carbohydrates": record["carbohydrates"],
            "carbohydrates_sugar": record["carbohydrates_sugar"],
            "fat": record["fat"],
            "fat_saturated": record["fat_saturated"],
            "fiber": record["fiber"],
            "sodium": record["sodium"],
            "code": None,
            "remote_id": food_id,
            "source_name": SOURCE_NAME,
            "source_url": source_url,
            "common_name": None,
            "brand": None,
            "license": license_obj,
            "license_title": record["name"],
            "license_object_url": object_url,
            "license_author": ATTRIBUTION,
            "license_author_url": ATTRIBUTION_URL,
            "license_derivative_source_url": "",
            "is_vegan": None,
            "is_vegetarian": None,
            "nutriscore": None,
        }

        with transaction.atomic():
            ingredient, created = Ingredient.objects.update_or_create(
                uuid=record["uuid"],
                defaults=defaults,
            )
            if created:
                created_count += 1
            else:
                updated_count += 1

            for unit in record["units"]:
                _, unit_created = IngredientWeightUnit.objects.update_or_create(
                    uuid=unit["uuid"],
                    defaults={
                        "ingredient": ingredient,
                        "name": unit["name"],
                        "gram": unit["gram"],
                    },
                )
                if unit_created:
                    unit_created_count += 1
                else:
                    unit_updated_count += 1

        if index % 250 == 0 or index == len(records):
            print(f"Imported {index}/{len(records)} foods")

    print(
        "Import complete: "
        f"ingredients created={created_count}, updated={updated_count}; "
        f"units created={unit_created_count}, updated={unit_updated_count}"
    )


def main():
    dry_run = env_bool("FINELI_DRY_RUN", True)
    limit = env_limit()
    requested_ids = env_food_ids()
    archive = download_archive()
    records, skipped, skipped_units = build_records(
        archive,
        requested_ids=requested_ids,
        limit=limit,
    )
    print_report(records, skipped, skipped_units, dry_run)
    if dry_run:
        print("Dry run complete; no database writes were made")
        return
    if not records:
        raise RuntimeError("Refusing to run an empty Fineli import")
    import_records(records)


main()
