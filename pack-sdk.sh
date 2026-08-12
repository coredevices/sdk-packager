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

PEBBLEOS_PATH=~/Core/pebbleos

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

configure_and_build_board() {
    local board=$1
    local platform_name=$2
    local js_engine=$3

    echo "Building for board: $board (platform: $platform_name, js_engine: $js_engine)"

    pbl_run ./pbl configure --board $board -DCONFIG_SHELL_SDK=y
    pbl_run ./pbl build qemu_image_micro qemu_image_spi
    mkdir build/sdk/$platform_name/qemu
    # Ship the firmware ELF as qemu_micro_flash.bin so pebble-tool's -kernel
    # invocation gets a proper vector table (matches `waf qemu_launch`).
    # Loading the flat binary causes timer/audio IRQs to stall the main loop.
    cp build/pebbleos.elf build/sdk/$platform_name/qemu/qemu_micro_flash.bin
    mv build/qemu_spi_flash.bin build/sdk/$platform_name/qemu/
    mv build/pebbleos.elf build/sdk/$platform_name/qemu/"$platform_name"_sdk_debug.elf
    mv build/resources/layouts.json.auto build/sdk/$platform_name/qemu/layouts.json
    bzip2 build/sdk/$platform_name/qemu/qemu_spi_flash.bin
}

# Build moddable boards from pebbleos-moddable for now
cd $PEBBLEOS_PATH
[ "$USE_NIX" -eq 1 ] || source .venv/bin/activate
pbl_run ./waf distclean

configure_and_build_board "qemu_gabbro" "gabbro" "moddable"
configure_and_build_board "qemu_emery" "emery" "moddable"
configure_and_build_board "qemu_flint" "flint" "none"
cd -
mkdir sdk-core
cp -r $PEBBLEOS_PATH/build/sdk sdk-core/pebble

# Build frozen platform SDKs (headers/shims only) using build_sdk.py
cd $PEBBLEOS_PATH
pbl_run python tools/build_sdk.py aplite basalt chalk diorite
cd -
cp -r $PEBBLEOS_PATH/build/sdk/aplite sdk-core/pebble/
cp -r $PEBBLEOS_PATH/build/sdk/basalt sdk-core/pebble/
cp -r $PEBBLEOS_PATH/build/sdk/chalk sdk-core/pebble/
cp -r $PEBBLEOS_PATH/build/sdk/diorite sdk-core/pebble/

mv sdk-core/pebble/package.json sdk-core/
mv sdk-core/pebble/use_requirements.json sdk-core/
mv sdk-core/pebble/requirements.txt sdk-core/

cat > sdk-core/manifest.json << EOF
{
    "requirements": $(cat sdk-core/use_requirements.json),
    "version": "$SDK_VERSION",
    "type": "sdk-core",
    "channel": ""
}
EOF

# Copy libpebble.a and qemu from old 4.4 SDK for frozen platforms
SDK_4_4_PATH=sdk-core-4.4/sdk-core/pebble
for platform in aplite basalt chalk diorite; do
    cp $SDK_4_4_PATH/$platform/lib/libpebble.a sdk-core/pebble/$platform/lib/
    cp -r $SDK_4_4_PATH/$platform/qemu sdk-core/pebble/$platform/
done

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
