set -e

# Repack an existing SDK release with freshly built emulator images.
# Everything else (headers, libs, toolchains) is reused from the base release.
if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 <base-sdk-version> <new-sdk-version>"
    echo "Example: $0 4.33 4.33.1"
    exit 1
fi

BASE_VERSION="$1"
NEW_VERSION="$2"

BASE_RELEASE_DIR=dist/releases/$BASE_VERSION
if [ ! -f "$BASE_RELEASE_DIR/sdk-core.tar.gz" ]; then
    echo "Error: $BASE_RELEASE_DIR/sdk-core.tar.gz not found"
    exit 1
fi

echo "Building hotfix $NEW_VERSION from $BASE_VERSION (new emulator images only)"

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

cd $PEBBLEOS_PATH
[ "$USE_NIX" -eq 1 ] || source .venv/bin/activate
pbl_run ./waf distclean

configure_and_build_board "qemu_gabbro" "gabbro" "moddable"
configure_and_build_board "qemu_emery" "emery" "moddable"
configure_and_build_board "qemu_flint" "flint" "none"
cd -

# Unpack the base release's sdk-core and swap in the new emulator images.
# Frozen platforms (aplite/basalt/chalk/diorite) keep their 4.4 qemu images.
WORK_DIR=build/hotfix
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
tar -xzf "$BASE_RELEASE_DIR/sdk-core.tar.gz" -C "$WORK_DIR"

for platform in gabbro emery flint; do
    rm -rf "$WORK_DIR/sdk-core/pebble/$platform/qemu"
    cp -r $PEBBLEOS_PATH/build/sdk/$platform/qemu "$WORK_DIR/sdk-core/pebble/$platform/qemu"
done

cat > "$WORK_DIR/sdk-core/manifest.json" << EOF
{
    "requirements": $(cat "$WORK_DIR/sdk-core/use_requirements.json"),
    "version": "$NEW_VERSION",
    "type": "sdk-core",
    "channel": ""
}
EOF

NEW_RELEASE_DIR=dist/releases/$NEW_VERSION
mkdir -p "$NEW_RELEASE_DIR"
tar -C "$WORK_DIR" -cvzSf "$NEW_RELEASE_DIR/sdk-core.tar.gz" sdk-core

# Toolchains contain no emulator images — reuse the base release's as-is.
for tc in toolchain-mac-x86_64 toolchain-mac-arm64 toolchain-linux-x86_64 toolchain-linux-aarch64; do
    cp "$BASE_RELEASE_DIR/$tc.tar.gz" "$NEW_RELEASE_DIR/"
done

rm -rf "$WORK_DIR"

echo "Done: $NEW_RELEASE_DIR"
