#!/usr/bin/env bash
# The D host with dub, the sketch with Processing's own preprocessor.
set -euo pipefail
cd "$(dirname "$0")"

nix-shell --run 'dub build --compiler=ldc2'
(cd textures && npx asc assembly/index.ts --target release)
NODE=$(readlink -f "$(command -v node)")

# Processing: the nix package on Linux; on macOS the portable app unpacked
# into .tools from github.com/processing/processing4's releases.
case "$(uname -s)" in
  Darwin)
    APP="$PWD/.tools/Processing.app"
    [ -d "$APP" ] || { echo "no $APP: unpack processing-*-macos-*-portable.zip into .tools"; exit 1; }
    CLI="$APP/Contents/MacOS/Processing"
    RES="$APP/Contents/app/resources"
    JAVA="$RES/jdk/bin/java"
    ;;
  *)
    P=$(readlink -f "$(dirname "$(readlink -f "$(command -v processing)")")/..")
    CLI=processing
    RES="$P/lib/app/resources"
    JAVA=$(nix-store -qR "$P" | grep -m1 -- '-openjdk-')/bin/java
    ;;
esac
# core.jar in the nix package, core-<version>.jar in the portable app.
CORE=$(find "$RES/core/library" -maxdepth 1 \( -name 'core.jar' -o -name 'core-[0-9]*.jar' \) | head -1)
[ -n "$CORE" ] || { echo "no core jar under $RES/core/library"; exit 1; }

tmp=$(mktemp -d)
"$CLI" cli --sketch="$PWD/pages" --output="$tmp" --force --build
# Its exit status has said 0 over a syntax error; what it leaves behind is the verdict.
[ -f "$tmp/pages.class" ] || { echo "build.sh: the sketch did not compile"; exit 1; }
rm -rf bin/classes "$tmp/source"
mv "$tmp" bin/classes

# Written with the paths this build used, so what runs is what was built.
cat > bin/renderer.new <<EOF
#!/usr/bin/env bash
exec "$JAVA" -Djava.awt.headless=true -Dsketches.node="$NODE" -Dsketches.gen="$PWD/textures/gen.js" -Dsketches.image="$PWD/image/walker.jpg" -cp "$PWD/bin/classes:$CORE" Runner "\$@"
EOF
chmod +x bin/renderer.new
mv bin/renderer.new bin/renderer
