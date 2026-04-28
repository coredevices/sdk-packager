#!/bin/bash
set -e

# xpack arm-none-eabi-gcc version to download
VERSION="${1:-14.2.1-1.1}"
echo "Using arm-none-eabi-gcc version: $VERSION"

# Moddable SDK version for moddable-tools
# Note: lin64 pulls the full tools bundle from $MODDABLE_VERSION, but overlays fontbm
# from $MODDABLE_VERSION_LIN64 because fontbm was dropped from lin64 builds after that version.
MODDABLE_VERSION="${2:-8.0.1}"
MODDABLE_VERSION_LIN64="5.7.0"
echo "Using Moddable SDK version: $MODDABLE_VERSION (lin64 fontbm overlay: $MODDABLE_VERSION_LIN64)"

XPACK_BASE_URL="https://github.com/xpack-dev-tools/arm-none-eabi-gcc-xpack/releases/download/v${VERSION}"
LINUX_X86_64_FILE="xpack-arm-none-eabi-gcc-${VERSION}-linux-x64.tar.gz"
LINUX_AARCH64_FILE="xpack-arm-none-eabi-gcc-${VERSION}-linux-arm64.tar.gz"
MAC_X86_64_FILE="xpack-arm-none-eabi-gcc-${VERSION}-darwin-x64.tar.gz"
MAC_ARM64_FILE="xpack-arm-none-eabi-gcc-${VERSION}-darwin-arm64.tar.gz"

# Create temp directory for downloads
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo "Downloading toolchains..."

# Download Linux x86_64 version
echo "Downloading Linux x86_64 toolchain..."
curl -L -o "$TEMP_DIR/$LINUX_X86_64_FILE" "$XPACK_BASE_URL/$LINUX_X86_64_FILE"

# Download Linux aarch64 version
echo "Downloading Linux aarch64 toolchain..."
curl -L -o "$TEMP_DIR/$LINUX_AARCH64_FILE" "$XPACK_BASE_URL/$LINUX_AARCH64_FILE"

# Download macOS x86_64 version
echo "Downloading macOS x86_64 toolchain..."
curl -L -o "$TEMP_DIR/$MAC_X86_64_FILE" "$XPACK_BASE_URL/$MAC_X86_64_FILE"

# Download macOS arm64 version
echo "Downloading macOS arm64 toolchain..."
curl -L -o "$TEMP_DIR/$MAC_ARM64_FILE" "$XPACK_BASE_URL/$MAC_ARM64_FILE"

# Clean up existing toolchain directories
rm -rf toolchain-linux-x86_64/arm-none-eabi
rm -rf toolchain-linux-aarch64/arm-none-eabi
rm -rf toolchain-mac-x86_64/arm-none-eabi
rm -rf toolchain-mac-arm64/arm-none-eabi

# Create toolchain directories if they don't exist
mkdir -p toolchain-linux-x86_64
mkdir -p toolchain-linux-aarch64
mkdir -p toolchain-mac-x86_64
mkdir -p toolchain-mac-arm64

# Extract Linux x86_64 toolchain
echo "Extracting Linux x86_64 toolchain..."
tar -xzf "$TEMP_DIR/$LINUX_X86_64_FILE" -C "$TEMP_DIR"
mv "$TEMP_DIR/xpack-arm-none-eabi-gcc-${VERSION}" toolchain-linux-x86_64/arm-none-eabi

# Extract Linux aarch64 toolchain
echo "Extracting Linux aarch64 toolchain..."
tar -xzf "$TEMP_DIR/$LINUX_AARCH64_FILE" -C "$TEMP_DIR"
mv "$TEMP_DIR/xpack-arm-none-eabi-gcc-${VERSION}" toolchain-linux-aarch64/arm-none-eabi

# Extract macOS x86_64 toolchain
echo "Extracting macOS x86_64 toolchain..."
tar -xzf "$TEMP_DIR/$MAC_X86_64_FILE" -C "$TEMP_DIR"
mv "$TEMP_DIR/xpack-arm-none-eabi-gcc-${VERSION}" toolchain-mac-x86_64/arm-none-eabi

# Extract macOS arm64 toolchain
echo "Extracting macOS arm64 toolchain..."
tar -xzf "$TEMP_DIR/$MAC_ARM64_FILE" -C "$TEMP_DIR"
mv "$TEMP_DIR/xpack-arm-none-eabi-gcc-${VERSION}" toolchain-mac-arm64/arm-none-eabi

echo ""
echo "Downloading QEMU from latest GitHub release..."

QEMU_RELEASE_TAG=$(gh release view --repo coredevices/qemu --json tagName --jq '.tagName')
echo "Using QEMU release: $QEMU_RELEASE_TAG"

for qemu_pair in \
    "qemu-pebble-linux-x86_64.tar.gz:toolchain-linux-x86_64" \
    "qemu-pebble-linux-arm64.tar.gz:toolchain-linux-aarch64" \
    "qemu-pebble-macos-x86_64.tar.gz:toolchain-mac-x86_64" \
    "qemu-pebble-macos-arm64.tar.gz:toolchain-mac-arm64"; do

    asset="${qemu_pair%%:*}"
    toolchain_dir="${qemu_pair##*:}"

    echo "Downloading ${asset}..."
    gh release download "$QEMU_RELEASE_TAG" --repo coredevices/qemu --pattern "$asset" --dir "$TEMP_DIR" --clobber
    mkdir -p "$toolchain_dir"
    tar -xzf "$TEMP_DIR/$asset" -C "$toolchain_dir"
    chmod +x "$toolchain_dir/bin/qemu-pebble"
    echo "Installed qemu-pebble to $toolchain_dir/bin/"
done

echo ""
echo "Downloading moddable-tools from Moddable SDK..."

MODDABLE_BASE_URL="https://github.com/Moddable-OpenSource/moddable/releases/download/${MODDABLE_VERSION}"
MODDABLE_BASE_URL_LIN64_OLD="https://github.com/Moddable-OpenSource/moddable/releases/download/${MODDABLE_VERSION_LIN64}"

# Download and extract the full moddable-tools zip for each platform
for platform_pair in \
    "moddable-tools-lin64.zip:toolchain-linux-x86_64" \
    "moddable-tools-lin64arm.zip:toolchain-linux-aarch64" \
    "moddable-tools-mac64.zip:toolchain-mac-x86_64" \
    "moddable-tools-mac64arm.zip:toolchain-mac-arm64"; do

    archive="${platform_pair%%:*}"
    toolchain_dir="${platform_pair##*:}"

    echo "Downloading ${archive}..."
    curl -L -o "$TEMP_DIR/$archive" "$MODDABLE_BASE_URL/$archive"

    rm -rf "$toolchain_dir/moddable-tools"
    mkdir -p "$toolchain_dir/moddable-tools"
    unzip -o "$TEMP_DIR/$archive" -d "$toolchain_dir/moddable-tools"
    find "$toolchain_dir/moddable-tools" -type f -exec chmod +x {} \;
    echo "Installed moddable-tools to $toolchain_dir/moddable-tools/"
done

# fontbm was dropped from lin64 builds after 5.7.0, so overlay fontbm from the older release
echo "Overlaying lin64 fontbm from Moddable SDK ${MODDABLE_VERSION_LIN64}..."
curl -L -o "$TEMP_DIR/moddable-tools-lin64-old.zip" "$MODDABLE_BASE_URL_LIN64_OLD/moddable-tools-lin64.zip"
unzip -o -j "$TEMP_DIR/moddable-tools-lin64-old.zip" fontbm -d "toolchain-linux-x86_64/moddable-tools"
chmod +x "toolchain-linux-x86_64/moddable-tools/fontbm"
echo "Installed fontbm to toolchain-linux-x86_64/moddable-tools/"

echo ""
echo "Done! Toolchains, QEMU, and moddable-tools downloaded for all platforms."