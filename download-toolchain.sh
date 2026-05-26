#!/bin/bash
set -e

# Parse flags. --build-moddable-tools / -b builds moddable-tools from the
# moddable submodule instead of downloading the prebuilt archives. Positional
# args (xpack version, moddable version) keep their previous meaning.
BUILD_MODDABLE_TOOLS=0
POSITIONAL=()
while [ $# -gt 0 ]; do
    case "$1" in
        --build-moddable-tools|-b)
            BUILD_MODDABLE_TOOLS=1
            shift
            ;;
        --)
            shift
            while [ $# -gt 0 ]; do POSITIONAL+=("$1"); shift; done
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done
set -- "${POSITIONAL[@]}"

# xpack arm-none-eabi-gcc version to download
VERSION="${1:-14.2.1-1.1}"
echo "Using arm-none-eabi-gcc version: $VERSION"

# Moddable SDK version for moddable-tools
# Note: lin64 pulls the full tools bundle from $MODDABLE_VERSION, but overlays fontbm
# from $MODDABLE_VERSION_LIN64 because fontbm was dropped from lin64 builds after that version.
MODDABLE_VERSION="${2:-8.1.1}"
MODDABLE_VERSION_LIN64="5.7.0"
echo "Using Moddable SDK version: $MODDABLE_VERSION (lin64 fontbm overlay: $MODDABLE_VERSION_LIN64)"
if [ "$BUILD_MODDABLE_TOOLS" -eq 1 ]; then
    echo "Build mode: building moddable-tools from ./moddable (fontbm still pulled from GitHub)"
fi

MODDABLE_BASE_URL="https://github.com/Moddable-OpenSource/moddable/releases/download/${MODDABLE_VERSION}"
MODDABLE_BASE_URL_LIN64_OLD="https://github.com/Moddable-OpenSource/moddable/releases/download/${MODDABLE_VERSION_LIN64}"

XPACK_BASE_URL="https://github.com/xpack-dev-tools/arm-none-eabi-gcc-xpack/releases/download/v${VERSION}"
LINUX_X86_64_FILE="xpack-arm-none-eabi-gcc-${VERSION}-linux-x64.tar.gz"
LINUX_AARCH64_FILE="xpack-arm-none-eabi-gcc-${VERSION}-linux-arm64.tar.gz"
MAC_X86_64_FILE="xpack-arm-none-eabi-gcc-${VERSION}-darwin-x64.tar.gz"
MAC_ARM64_FILE="xpack-arm-none-eabi-gcc-${VERSION}-darwin-arm64.tar.gz"

# Create temp directory for downloads
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Trim an extracted xpack arm-none-eabi toolchain in-place to drop multilib
# variants and tools pebbleos doesn't use. See README for the rationale.
trim_arm_toolchain() {
    local root="$1"
    local newlib="$root/arm-none-eabi/lib/thumb"
    local gcclib="$root/lib/gcc/arm-none-eabi/14.2.1/thumb"

    # Multilib variants pebbleos targets (verified via gcc --print-multi-directory):
    #   cortex-m3              -> thumb/v7-m/nofp           (aplite)
    #   cortex-m4 (QEMU)       -> thumb/v7e-m/nofp          (QEMU_PEBBLE_ARMCM4)
    #   cortex-m4 + fpv4-sp    -> thumb/v7e-m+fp/softfp     (NRF52, basalt/chalk/diorite/emery hw)
    #   cortex-m33+nofp+nodsp  -> thumb/v8-m.main/nofp      (QEMU_PEBBLE_ARMCM33)
    #   star-mc1 + fpv5-sp     -> thumb/v8-m.main+fp/softfp (SF32LB52)
    local keep=(v7-m v7e-m v7e-m+fp v8-m.main v8-m.main+fp)

    for dir in "$newlib" "$gcclib"; do
        [ -d "$dir" ] || continue
        for variant in "$dir"/*/; do
            local name
            name=$(basename "$variant")
            local keep_it=0
            for k in "${keep[@]}"; do
                if [ "$name" = "$k" ]; then keep_it=1; break; fi
            done
            if [ $keep_it -eq 0 ]; then
                rm -rf "$variant"
            fi
        done
    done

    # Fortran: unused.
    rm -f "$root/bin/arm-none-eabi-gfortran"
    rm -f "$root/libexec/gcc/arm-none-eabi/14.2.1/f951"
    rm -f "$root/arm-none-eabi/lib/libgfortran.a" "$root/arm-none-eabi/lib/libgfortran.spec"
    find "$root/arm-none-eabi/lib/thumb" -name 'libgfortran.a' -delete 2>/dev/null || true
    find "$root/lib/gcc/arm-none-eabi/14.2.1" -name 'libgfortran.a' -delete 2>/dev/null || true

    # ld.gold: alternative linker, pebbleos uses default ld.bfd.
    rm -f "$root/bin/arm-none-eabi-ld.gold"
    rm -f "$root/arm-none-eabi/bin/ld.gold"

    # lto-dump: diagnostic tool. Actual LTO uses libexec/.../lto1 + lto-wrapper.
    rm -f "$root/bin/arm-none-eabi-lto-dump"
}

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
trim_arm_toolchain toolchain-linux-x86_64/arm-none-eabi

# Extract Linux aarch64 toolchain
echo "Extracting Linux aarch64 toolchain..."
tar -xzf "$TEMP_DIR/$LINUX_AARCH64_FILE" -C "$TEMP_DIR"
mv "$TEMP_DIR/xpack-arm-none-eabi-gcc-${VERSION}" toolchain-linux-aarch64/arm-none-eabi
trim_arm_toolchain toolchain-linux-aarch64/arm-none-eabi

# Extract macOS x86_64 toolchain
echo "Extracting macOS x86_64 toolchain..."
tar -xzf "$TEMP_DIR/$MAC_X86_64_FILE" -C "$TEMP_DIR"
mv "$TEMP_DIR/xpack-arm-none-eabi-gcc-${VERSION}" toolchain-mac-x86_64/arm-none-eabi
trim_arm_toolchain toolchain-mac-x86_64/arm-none-eabi

# Extract macOS arm64 toolchain
echo "Extracting macOS arm64 toolchain..."
tar -xzf "$TEMP_DIR/$MAC_ARM64_FILE" -C "$TEMP_DIR"
mv "$TEMP_DIR/xpack-arm-none-eabi-gcc-${VERSION}" toolchain-mac-arm64/arm-none-eabi
trim_arm_toolchain toolchain-mac-arm64/arm-none-eabi

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
if [ "$BUILD_MODDABLE_TOOLS" -eq 1 ]; then
    echo "Building moddable-tools from ./moddable..."

    if [ ! -d "moddable/build/makefiles" ]; then
        echo "Error: moddable submodule not initialized (moddable/build/makefiles missing)."
        echo "Run: git submodule update --init --recursive"
        exit 1
    fi

    # Linux x86_64 via Docker
    echo "Building linux x86_64 moddable-tools (docker)..."
    docker build --platform linux/amd64 -f Dockerfile-moddable-tools -t moddable-pebble-amd64 .
    rm -rf toolchain-linux-x86_64/moddable-tools
    docker run --rm --platform linux/amd64 -v "$(pwd):/output" moddable-pebble-amd64 \
        sh -c 'cp -r $MODDABLE/build/bin/lin/release /output/toolchain-linux-x86_64/moddable-tools'

    # Linux aarch64 via Docker
    echo "Building linux aarch64 moddable-tools (docker)..."
    docker build --platform linux/arm64 -f Dockerfile-moddable-tools -t moddable-pebble-arm64 .
    rm -rf toolchain-linux-aarch64/moddable-tools
    docker run --rm --platform linux/arm64 -v "$(pwd):/output" moddable-pebble-arm64 \
        sh -c 'cp -r $MODDABLE/build/bin/lin/release /output/toolchain-linux-aarch64/moddable-tools'

    # macOS universal binary, fanned out to both arch dirs
    echo "Building mac universal moddable-tools (native)..."
    (
        export MODDABLE="$(pwd)/moddable"
        export PATH="${MODDABLE}/build/bin/mac/release:$PATH"
        export PLAT=macuniversal
        export MACOS_ARCH="-arch x86_64 -arch arm64"
        cd "${MODDABLE}/build/makefiles/mac"
        make
    )
    rm -rf toolchain-mac-x86_64/moddable-tools toolchain-mac-arm64/moddable-tools
    cp -r "$(pwd)/moddable/build/bin/mac/release" toolchain-mac-x86_64/moddable-tools
    cp -r "$(pwd)/moddable/build/bin/mac/release" toolchain-mac-arm64/moddable-tools

    # Source builds don't produce fontbm — overlay it from the Moddable SDK
    # release archives for every platform except lin64 (handled below from
    # the older release).
    for fontbm_pair in \
        "moddable-tools-lin64arm.zip:toolchain-linux-aarch64" \
        "moddable-tools-mac64.zip:toolchain-mac-x86_64" \
        "moddable-tools-mac64arm.zip:toolchain-mac-arm64"; do

        archive="${fontbm_pair%%:*}"
        toolchain_dir="${fontbm_pair##*:}"

        echo "Overlaying fontbm into $toolchain_dir/moddable-tools from $archive..."
        curl -L -o "$TEMP_DIR/$archive" "$MODDABLE_BASE_URL/$archive"
        unzip -o -j "$TEMP_DIR/$archive" fontbm -d "$toolchain_dir/moddable-tools"
        chmod +x "$toolchain_dir/moddable-tools/fontbm"
    done
else
    echo "Downloading moddable-tools from Moddable SDK..."

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
fi

# fontbm was dropped from lin64 builds after 5.7.0, so overlay fontbm from the older release
echo "Overlaying lin64 fontbm from Moddable SDK ${MODDABLE_VERSION_LIN64}..."
curl -L -o "$TEMP_DIR/moddable-tools-lin64-old.zip" "$MODDABLE_BASE_URL_LIN64_OLD/moddable-tools-lin64.zip"
unzip -o -j "$TEMP_DIR/moddable-tools-lin64-old.zip" fontbm -d "toolchain-linux-x86_64/moddable-tools"
chmod +x "toolchain-linux-x86_64/moddable-tools/fontbm"
echo "Installed fontbm to toolchain-linux-x86_64/moddable-tools/"

echo ""
if [ "$BUILD_MODDABLE_TOOLS" -eq 1 ]; then
    echo "Done! Toolchains and QEMU downloaded, moddable-tools built from source, for all platforms."
else
    echo "Done! Toolchains, QEMU, and moddable-tools downloaded for all platforms."
fi