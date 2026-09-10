#!/bin/bash
# Build the ThirdReality matter-server release tarball from the fork working tree.
# Prototype for tr-release.yml. Usage: build-tarball.sh <version>   (e.g. 1.4.0-tr.1)
# Requires: repo already built (npm run build), run from anywhere.
set -euo pipefail

VER="${1:?usage: build-tarball.sh <version>}"
REPO=/root/matter-js/matter.js
OUT=/root/m2m-dist
BUNDLED=(custom-clusters ws-client ws-controller dashboard ble-proxy mqtt-bridge)

cd "$REPO"

echo "[1] apply version $VER"
npm run version -- --set "$VER" >/dev/null
# nacho's --apply also syncs package-lock (minutes on this box); we only need package.json
# versions for pack, so do the apply step directly.
node - "$VER" <<'EOF'
const fs = require("fs");
const ver = process.argv[2];
const pkgs = ["custom-clusters", "ws-controller", "ws-client", "dashboard", "ble-proxy", "mqtt-bridge", "matter-server"];
for (const p of pkgs) {
    const path = `packages/${p}/package.json`;
    const pkg = JSON.parse(fs.readFileSync(path, "utf8"));
    pkg.version = ver;
    for (const section of ["dependencies", "devDependencies"]) {
        for (const dep of Object.keys(pkg[section] ?? {})) {
            if (dep.startsWith("@matter-server/")) pkg[section][dep] = ver;
        }
    }
    fs.writeFileSync(path, JSON.stringify(pkg, null, 4) + "\n");
}
EOF

echo "[2] hoist external deps of bundled packages into matter-server"
node - <<'EOF'
const fs = require("fs");
const bundled = ["custom-clusters", "ws-client", "ws-controller", "dashboard", "ble-proxy", "mqtt-bridge"];
const mainPath = "packages/matter-server/package.json";
const main = JSON.parse(fs.readFileSync(mainPath, "utf8"));
for (const p of bundled) {
    const deps = JSON.parse(fs.readFileSync(`packages/${p}/package.json`, "utf8")).dependencies ?? {};
    for (const [name, range] of Object.entries(deps)) {
        if (name.startsWith("@matter-server/")) continue;
        if (main.dependencies[name] === undefined) {
            main.dependencies[name] = range;
            console.log(`  + ${name}@${range} (from ${p})`);
        }
    }
}
main.dependencies = Object.fromEntries(Object.entries(main.dependencies).sort(([a], [b]) => a.localeCompare(b)));
fs.writeFileSync(mainPath, JSON.stringify(main, null, 4) + "\n");
EOF

echo "[3] pack workspace packages"
rm -f "$OUT"/matter-server-*.tgz "$OUT"/matter-server-*.sha256
npm pack -w matter-server --pack-destination "$OUT" >/dev/null 2>&1
for p in "${BUNDLED[@]}"; do
    npm pack -w "@matter-server/$p" --pack-destination "$OUT" >/dev/null 2>&1
done

echo "[4] assemble bundled tarball (npm workspace bundling is broken for symlinks)"
cd "$OUT"
rm -rf assemble && mkdir assemble && cd assemble
tar -xzf "../matter-server-$VER.tgz"
mkdir -p package/node_modules/@matter-server
for p in "${BUNDLED[@]}"; do
    mkdir -p "package/node_modules/@matter-server/$p"
    tar -xzf "../matter-server-$p-$VER.tgz" -C "package/node_modules/@matter-server/$p" --strip-components=1
done
tar -czf "../matter-server-$VER.tgz" package
cd .. && rm -rf assemble
for p in "${BUNDLED[@]}"; do rm -f "matter-server-$p-$VER.tgz"; done

echo "[5] smoke-verify the tarball"
for p in "${BUNDLED[@]}"; do
    tar -tzf "matter-server-$VER.tgz" "package/node_modules/@matter-server/$p/package.json" >/dev/null
done
rm -rf /tmp/tgz-verify && mkdir /tmp/tgz-verify && cd /tmp/tgz-verify
npm install --omit=dev --no-audit --no-fund "$OUT/matter-server-$VER.tgz" >/dev/null 2>&1
installed=$(node -p "require('./node_modules/matter-server/package.json').version")
[[ "$installed" == "$VER" ]] || { echo "FATAL: installed version $installed != $VER"; exit 1; }
node node_modules/matter-server/dist/esm/MatterServer.js --help 2>/dev/null | grep -q "mqtt-url" \
    || { echo "FATAL: --help lacks mqtt-url"; exit 1; }
rm -rf /tmp/tgz-verify

echo "[6] checksum + restore working tree"
cd "$OUT" && sha256sum "matter-server-$VER.tgz" > "matter-server-$VER.tgz.sha256"
cd "$REPO" && git checkout -- version.txt packages/ 2>/dev/null || true

echo "DONE: $OUT/matter-server-$VER.tgz"
(cd "$OUT" && sha256sum -c "matter-server-$VER.tgz.sha256")
