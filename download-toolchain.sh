#!/bin/bash
set -e

# xpack arm-none-eabi-gcc version to download
VERSION="${1:-14.2.1-1.1}"
echo "Using arm-none-eabi-gcc version: $VERSION"

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
echo "Downloading QEMU from latest GitHub Actions run..."

# Get the latest successful run ID from coredevices/qemu
QEMU_RUN_ID=$(gh run list --repo coredevices/qemu --workflow build.yaml --status success --limit 1 --json databaseId --jq '.[0].databaseId')
echo "Using QEMU build run ID: $QEMU_RUN_ID"

# Create bin and lib directories
mkdir -p toolchain-linux-x86_64/bin
mkdir -p toolchain-linux-aarch64/bin
mkdir -p toolchain-linux-x86_64/lib
mkdir -p toolchain-linux-aarch64/lib
mkdir -p toolchain-linux-aarch64/lib/pc-bios
mkdir -p toolchain-linux-x86_64/lib/pc-bios
mkdir -p toolchain-mac-x86_64/bin
mkdir -p toolchain-mac-x86_64/lib
mkdir -p toolchain-mac-arm64/bin
mkdir -p toolchain-mac-arm64/lib

# Download and install Linux x86_64 QEMU
echo "Downloading Linux x86_64 QEMU..."
gh run download $QEMU_RUN_ID --repo coredevices/qemu --name qemu-system-arm-linux-x64 --dir "$TEMP_DIR/qemu-linux-x64"
gh run download $QEMU_RUN_ID --repo coredevices/qemu --name pc-bios-linux-x64 --dir "$TEMP_DIR/pc-bios-linux-x64"
mv "$TEMP_DIR/qemu-linux-x64/qemu-system-arm" toolchain-linux-x86_64/bin/qemu-pebble
mv "$TEMP_DIR/pc-bios-linux-x64"/* toolchain-linux-x86_64/lib/pc-bios/

# Download and install Linux aarch64 QEMU
echo "Downloading Linux aarch64 QEMU..."
gh run download $QEMU_RUN_ID --repo coredevices/qemu --name qemu-system-arm-linux-arm64 --dir "$TEMP_DIR/qemu-linux-arm64"
gh run download $QEMU_RUN_ID --repo coredevices/qemu --name pc-bios-linux-arm64 --dir "$TEMP_DIR/pc-bios-linux-arm64"
mv "$TEMP_DIR/qemu-linux-arm64/qemu-system-arm" toolchain-linux-aarch64/bin/qemu-pebble
mv "$TEMP_DIR/pc-bios-linux-arm64"/* toolchain-linux-aarch64/lib/pc-bios/

# Download and install macOS x86_64 QEMU
echo "Downloading macOS x86_64 QEMU..."
gh run download $QEMU_RUN_ID --repo coredevices/qemu --name qemu-system-arm-macos-x64 --dir "$TEMP_DIR/qemu-mac-x64"
gh run download $QEMU_RUN_ID --repo coredevices/qemu --name lib-macos-x64 --dir "$TEMP_DIR/lib-mac-x64"
mv "$TEMP_DIR/qemu-mac-x64/qemu-system-arm" toolchain-mac-x86_64/bin/qemu-pebble
mv "$TEMP_DIR/lib-mac-x64"/* toolchain-mac-x86_64/lib/

# Download and install macOS arm64 QEMU
echo "Downloading macOS arm64 QEMU..."
gh run download $QEMU_RUN_ID --repo coredevices/qemu --name qemu-system-arm-macos-arm64 --dir "$TEMP_DIR/qemu-mac-arm64"
gh run download $QEMU_RUN_ID --repo coredevices/qemu --name lib-macos-arm64 --dir "$TEMP_DIR/lib-mac-arm64"
mv "$TEMP_DIR/qemu-mac-arm64/qemu-system-arm" toolchain-mac-arm64/bin/qemu-pebble
mv "$TEMP_DIR/lib-mac-arm64"/* toolchain-mac-arm64/lib/

echo ""
echo "Done! Toolchains and QEMU downloaded for all platforms."