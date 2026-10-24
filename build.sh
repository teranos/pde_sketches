#!/usr/bin/env bash
# The D host with dub, the sketch with Processing's own preprocessor.
set -euo pipefail
cd "$(dirname "$0")"

if command -v nix-shell >/dev/null; then
    nix-shell --run 'dub build --compiler=ldc2'
else
    dub build --compiler=ldc2
fi
(cd textures && npx asc assembly/index.ts --target release)
NODE=$(readlink -f "$(command -v node)")

if [[ "$(uname)" == Darwin ]]; then
    # Processing.app brings its own JDK and core.jar; they are found inside it
    # rather than at fixed paths, which move between Processing releases.
    APP=${PROCESSING_APP:-/Applications/Processing.app}
    PROCESSING=${PROCESSING:-$APP/Contents/MacOS/Processing}
    CORE=${CORE:-$(find "$APP" -name core.jar -path '*core/library*' | head -1)}
    JAVA=${JAVA:-$(find "$APP" -path '*/bin/java' -type f | head -1)}
    [[ -x "$PROCESSING" && -f "$CORE" && -x "$JAVA" ]] || {
        echo "build.sh: Processing not found in $APP (set PROCESSING_APP, or PROCESSING, CORE and JAVA)" >&2
        exit 1
    }
else
    PROCESSING=processing
    P=$(readlink -f "$(dirname "$(readlink -f "$(command -v processing)")")/..")
    CORE="$P/lib/app/resources/core/library/core.jar"
    JAVA=$(nix-store -qR "$P" | grep -m1 -- '-openjdk-')/bin/java
fi

tmp=$(mktemp -d)
"$PROCESSING" cli --sketch="$PWD/pages" --output="$tmp" --force --build
rm -rf bin/classes "$tmp/source"
mv "$tmp" bin/classes

# Written with the paths this build used, so what runs is what was built.
cat > bin/renderer.new <<EOF
#!/usr/bin/env bash
exec "$JAVA" -Djava.awt.headless=true -Dsketches.node="$NODE" -Dsketches.gen="$PWD/textures/gen.js" -cp "$PWD/bin/classes:$CORE" Runner "\$@"
EOF
chmod +x bin/renderer.new
mv bin/renderer.new bin/renderer
