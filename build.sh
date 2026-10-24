#!/usr/bin/env bash
# The D host with dub, the sketch with Processing's own preprocessor.
set -euo pipefail
cd "$(dirname "$0")"

nix-shell --run 'dub build --compiler=ldc2'
(cd textures && npx asc assembly/index.ts --target release)
NODE=$(readlink -f "$(command -v node)")

P=$(readlink -f "$(dirname "$(readlink -f "$(command -v processing)")")/..")
CORE="$P/lib/app/resources/core/library/core.jar"
JAVA=$(nix-store -qR "$P" | grep -m1 -- '-openjdk-')/bin/java

tmp=$(mktemp -d)
processing cli --sketch="$PWD/pages" --output="$tmp" --force --build
rm -rf bin/classes "$tmp/source"
mv "$tmp" bin/classes

# Written with the paths this build used, so what runs is what was built.
cat > bin/renderer.new <<EOF
#!/usr/bin/env bash
exec "$JAVA" -Djava.awt.headless=true -Dsketches.node="$NODE" -Dsketches.gen="$PWD/textures/gen.js" -cp "$PWD/bin/classes:$CORE" Runner "\$@"
EOF
chmod +x bin/renderer.new
mv bin/renderer.new bin/renderer
