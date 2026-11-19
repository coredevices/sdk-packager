set -e

# Check if SDK version argument is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <sdk-version>"
    echo "Example: $0 4.9"
    exit 1
fi

SDK_VERSION="$1"
echo "Building SDK version: $SDK_VERSION"

rm -rf sdk-core

rm -rf toolchain-mac-x86_64/moddable/
rm -rf toolchain-mac-arm64/moddable/
rm -rf toolchain-linux-x86_64/moddable/
rm -rf toolchain-linux-aarch64/moddable/

rm -rf moddable/documentation

rm -rf build/
rm -rf dist/releases/
rm -rf moddable/build/bin
rm -rf moddable/build/tmp

cp -r moddable toolchain-mac-x86_64/moddable
cp -r moddable toolchain-mac-arm64/moddable
cp -r moddable toolchain-linux-x86_64/moddable
cp -r moddable toolchain-linux-aarch64/moddable

rm -rf toolchain-linux-x86_64/moddable/.git
rm -rf toolchain-linux-aarch64/moddable/.git
rm -rf toolchain-mac-x86_64/moddable/.git
rm -rf toolchain-mac-arm64/moddable/.git

PEBBLEOS_PATH=${PEBBLEOS_PATH:-$HOME/Projects/Core/pebbleos}

# On Nix systems, run pebbleos build commands inside the repo's flake dev
# shell — its shellHook provides the toolchain and activates the venv.
# Otherwise fall back to sourcing the existing .venv directly.
if command -v nix >/dev/null 2>&1 && [ -f "$PEBBLEOS_PATH/flake.nix" ]; then
    USE_NIX=1
    echo "Nix detected: running pebbleos builds via 'nix develop'"
    pbl_run() { nix develop "$PEBBLEOS_PATH" --command "$@"; }
else
    USE_NIX=0
    pbl_run() { "$@"; }
fi

# `pbl sdk` builds every board sdk/boards.yml lists with the SDK shell and
# its emulator, adds the frozen platforms, and writes the sdk-core tree with
# its manifest. The libpebble.a and emulator of the frozen platforms are the
# ones of the 4.4 SDK: they are what those platforms were frozen with.
FROZEN_PATH="$(pwd)/sdk-core-4.4/sdk-core/pebble"
SDK_BUILD_PATH="$PEBBLEOS_PATH/build-sdk"

cd "$PEBBLEOS_PATH"
[ "$USE_NIX" -eq 1 ] || source .venv/bin/activate
# Start from a clean tree so nothing stale can end up in a package.
rm -rf "$SDK_BUILD_PATH"
pbl_run pbl sdk "$SDK_VERSION" --frozen "$FROZEN_PATH"
cd -

# -a keeps the links from a platform to the headers and library of its ABI.
cp -a "$SDK_BUILD_PATH/sdk-core" sdk-core

mkdir build/

tar -cvzSf sdk-core.tar.gz sdk-core

mkdir dist/releases/
mkdir dist/releases/$SDK_VERSION
mv sdk-core.tar.gz dist/releases/$SDK_VERSION

tar -cvzSf toolchain-mac-x86_64.tar.gz toolchain-mac-x86_64
mv toolchain-mac-x86_64.tar.gz dist/releases/$SDK_VERSION/

tar -cvzSf toolchain-mac-arm64.tar.gz toolchain-mac-arm64
mv toolchain-mac-arm64.tar.gz dist/releases/$SDK_VERSION/

tar -cvzSf toolchain-linux-x86_64.tar.gz toolchain-linux-x86_64
mv toolchain-linux-x86_64.tar.gz dist/releases/$SDK_VERSION/

tar -cvzSf toolchain-linux-aarch64.tar.gz toolchain-linux-aarch64
mv toolchain-linux-aarch64.tar.gz dist/releases/$SDK_VERSION/
