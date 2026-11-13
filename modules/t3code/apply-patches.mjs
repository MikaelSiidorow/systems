// Apply patches.nix (passed as JSON) to T3's built server bundle in place.
// Usage: node apply-patches.mjs <dist> <patches.json>
import { readFileSync, readdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { execFileSync } from "node:child_process";

const [dist, specPath] = process.argv.slice(2);
const { helpers, patches } = JSON.parse(readFileSync(specPath, "utf8"));
const fail = (message) => {
  console.error(`t3code: ${message}`);
  process.exit(1);
};
const escape = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

const files = new Map(
  readdirSync(dist)
    .filter((name) => name.endsWith(".mjs"))
    .map((name) => [name, readFileSync(join(dist, name), "utf8")]),
);
const original = new Map(files);

for (const { find, regex, replace } of patches) {
  const pattern = new RegExp(regex ? find : escape(find), "g");
  const hits = [...files].flatMap(([name, text]) => (text.match(pattern) ?? []).map(() => name));
  if (hits.length !== 1) fail(`expected one '${find}' in ${dist}, found ${hits.length}`);
  files.set(hits[0], files.get(hits[0]).replace(pattern, () => replace));
}

// Import the helpers each patched file now uses from the Effect chunk it
// imports. That chunk keeps Effect's own names under a comment naming each
// effect/dist module, and exports them under aliases that shift per release.
function resolve(effectChunk, spec, local) {
  const [module, name] = spec.split(":");
  let section = null;
  const defined = [];
  for (const line of files.get(effectChunk).split("\n")) {
    const header = line.match(/^\/\/ .*\/effect\/dist\/(.*)$/);
    if (header) section = header[1];
    const definition = line.match(new RegExp(`^(?:const|function) (${escape(name)}(?:\\$[0-9]+)?)[ (=]`));
    if (section === module && definition) defined.push(definition[1]);
  }
  const aliases = defined.length === 1
    ? [...files.get(effectChunk).matchAll(new RegExp(`(?:^|[{\\s,])${escape(defined[0])} as ([A-Za-z0-9_$]+)[,} ]`, "gm"))]
    : [];
  if (aliases.length !== 1) fail(`cannot import ${module} ${name} from ${effectChunk} as ${local}`);
  return `${aliases[0][1]} as ${local}`;
}

for (const [name, text] of files) {
  if (text === original.get(name)) continue;
  const used = Object.keys(helpers).filter((local) => text.includes(local));
  if (used.length > 0) {
    const effectChunk = text.match(/^import \{.*\} from "\.\/(Effect-[^"]+\.mjs)";$/m)?.[1];
    if (!effectChunk) fail(`${name} imports no Effect chunk`);
    const taken = used.filter((local) => original.get(name).includes(local));
    if (taken.length > 0) fail(`${name} already uses ${taken.join(", ")}`);
    const imports = used.map((local) => resolve(effectChunk, helpers[local], local));
    // The chunk ends in a sourceMappingURL comment without a newline.
    files.set(name, `${text}\nimport { ${imports.join(", ")} } from "./${effectChunk}";\n`);
  }
  writeFileSync(join(dist, name), files.get(name));
  execFileSync(process.execPath, ["--check", join(dist, name)], { stdio: "inherit" });
}
