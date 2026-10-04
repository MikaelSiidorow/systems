import os
import subprocess

from django.contrib.auth import get_user_model
from django.db import connection
from wger.gym.models import GymAdminConfig


MARKER = "initial-fixtures-v1"


def ensure_marker_table():
    with connection.cursor() as cursor:
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS public.wger_bootstrap_state (
                key text PRIMARY KEY,
                completed_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
        """)


def marker_exists():
    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT 1 FROM public.wger_bootstrap_state WHERE key = %s",
            [MARKER],
        )
        return cursor.fetchone() is not None


def record_marker():
    with connection.cursor() as cursor:
        cursor.execute(
            """
            INSERT INTO public.wger_bootstrap_state (key)
            VALUES (%s)
            ON CONFLICT (key) DO NOTHING
            """,
            [MARKER],
        )


ensure_marker_table()

if marker_exists():
    print("Initial fixture marker exists")
else:
    User = get_user_model()

    if GymAdminConfig.objects.filter(pk=1).exists():
        print("Recording marker for an existing initialized database")
        record_marker()
    elif User.objects.exists():
        raise RuntimeError("Refusing to load fixed-PK fixtures into a non-empty database")
    else:
        print("Loading initial fixtures")
        connection.close()
        subprocess.run(["wger", "load-fixtures"], check=True)
        record_marker()
        print("Recorded initial fixture marker")

    user, created = User.objects.get_or_create(
        username="admin",
        defaults={"is_staff": True, "is_superuser": True},
    )
    if created or user.check_password("adminadmin"):
        user.set_password(os.environ["ADMIN_PASSWORD"])
        user.save(update_fields=["password"])
        print("Secured the bootstrap administrator account")
    else:
        print("Administrator password was already changed; leaving it untouched")
