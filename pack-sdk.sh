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

rm -rf build/
rm -rf dist/releases/

PEBBLEOS_PATH=~/Core/pebbleos

cd $PEBBLEOS_PATH && source .venv/bin/activate
./waf distclean

configure_and_build_board() {
    local board=$1
    local platform_name=$2
    
    echo "Building for board: $board (platform: $platform_name)"
  
    ./waf configure --qemu --board $board --sdkshell
    ./waf build qemu_image_micro qemu_image_spi
    mkdir build/sdk/$platform_name/qemu
    mv build/qemu_micro_flash.bin build/sdk/$platform_name/qemu/
    mv build/qemu_spi_flash.bin build/sdk/$platform_name/qemu/
    mv build/src/fw/tintin_fw.elf build/sdk/$platform_name/qemu/"$platform_name"_sdk_debug.elf
    mv build/resources/layouts.json.auto build/sdk/$platform_name/qemu/layouts.json
    bzip2 build/sdk/$platform_name/qemu/qemu_spi_flash.bin
}

configure_and_build_board "spalding_gabbro" "gabbro"
configure_and_build_board "silk_flint" "flint"
configure_and_build_board "snowy_emery" "emery"
configure_and_build_board "silk_bb2" "diorite"
configure_and_build_board "spalding_bb2" "chalk"
configure_and_build_board "snowy_bb2" "basalt"

cd -
mkdir sdk-core
cp -r $PEBBLEOS_PATH/build/sdk sdk-core/pebble

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

# We dont build for Aplite anymore, so copy from 4.4
SDK_4_4_PATH=sdk-core-4.4/sdk-core/pebble
cp -r $SDK_4_4_PATH/aplite sdk-core/pebble/

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
