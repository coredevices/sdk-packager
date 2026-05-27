set -e

usage() {
    cat <<EOF
Usage: $0 [options] <sdk-version>

Options:
  -t, --targets <list>   Comma-separated targets to pack (default: all).
                         Valid: linux-x86_64, linux-aarch64,
                                mac-x86_64, mac-arm64
  -h, --help             Show this message.

Example: $0 4.9
         $0 -t linux-x86_64,mac-arm64 4.9
EOF
}

TARGETS_ARG=""
POSITIONAL=()
while [ $# -gt 0 ]; do
    case "$1" in
        --targets|-t) TARGETS_ARG="$2"; shift 2 ;;
        --targets=*) TARGETS_ARG="${1#*=}"; shift ;;
        --help|-h) usage; exit 0 ;;
        --) shift; while [ $# -gt 0 ]; do POSITIONAL+=("$1"); shift; done ;;
        *) POSITIONAL+=("$1"); shift ;;
    esac
done
set -- "${POSITIONAL[@]}"

if [ -z "$1" ]; then
    usage >&2
    exit 1
fi

SDK_VERSION="$1"

ALL_TARGETS=(linux-x86_64 linux-aarch64 mac-x86_64 mac-arm64)
if [ -z "$TARGETS_ARG" ]; then
    TARGETS=("${ALL_TARGETS[@]}")
else
    IFS=',' read -r -a TARGETS <<< "$TARGETS_ARG"
    for t in "${TARGETS[@]}"; do
        case " ${ALL_TARGETS[*]} " in
            *" $t "*) ;;
            *) echo "Unknown target: $t (valid: ${ALL_TARGETS[*]})" >&2; exit 1 ;;
        esac
    done
fi

echo "Building SDK version: $SDK_VERSION"
echo "Targets: ${TARGETS[*]}"

rm -rf sdk-core

for target in "${TARGETS[@]}"; do
    rm -rf "toolchain-$target/moddable/"
done

rm -rf moddable/documentation

rm -rf build/
rm -rf dist/releases/

for target in "${TARGETS[@]}"; do
    cp -r moddable "toolchain-$target/moddable"
done

if [ -z "${PEBBLEOS_PATH}" ]; then
    PEBBLEOS_PATH='~/Core/pebbleos'
fi

configure_and_build_board() {
    local board=$1
    local platform_name=$2
    local js_engine=$3

    echo "Building for board: $board (platform: $platform_name, js_engine: $js_engine)"

    JS_ENGINE=$js_engine ./waf configure --board $board --sdkshell
    ./waf build qemu_image_micro qemu_image_spi
    mkdir build/sdk/$platform_name/qemu
    # Ship the firmware ELF as qemu_micro_flash.bin so pebble-tool's -kernel
    # invocation gets a proper vector table (matches `waf qemu_launch`).
    # Loading the flat binary causes timer/audio IRQs to stall the main loop.
    cp build/src/fw/tintin_fw.elf build/sdk/$platform_name/qemu/qemu_micro_flash.bin
    mv build/qemu_spi_flash.bin build/sdk/$platform_name/qemu/
    mv build/src/fw/tintin_fw.elf build/sdk/$platform_name/qemu/"$platform_name"_sdk_debug.elf
    mv build/resources/layouts.json.auto build/sdk/$platform_name/qemu/layouts.json
    bzip2 build/sdk/$platform_name/qemu/qemu_spi_flash.bin
}

# Build moddable boards from pebbleos-moddable for now
cd $PEBBLEOS_PATH && source .venv/bin/activate
./waf distclean

configure_and_build_board "qemu_gabbro" "gabbro" "moddable"
configure_and_build_board "qemu_emery" "emery" "moddable"
configure_and_build_board "qemu_flint" "flint" "none"
cd -
mkdir sdk-core
cp -r $PEBBLEOS_PATH/build/sdk sdk-core/pebble

# Build frozen platform SDKs (headers/shims only) using build_sdk.py
cd $PEBBLEOS_PATH
python tools/build_sdk.py aplite basalt chalk diorite
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

for target in "${TARGETS[@]}"; do
    tar -cvzSf "toolchain-$target.tar.gz" "toolchain-$target"
    mv "toolchain-$target.tar.gz" "dist/releases/$SDK_VERSION/"
done
