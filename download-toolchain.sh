#!/bin/bash
set -e

usage() {
    cat <<EOF
Usage: $0 [options] [xpack-version] [moddable-version]

Options:
  -b, --build-moddable-tools   Build moddable-tools from ./moddable submodule
                               instead of downloading prebuilt archives.
  -t, --targets <list>         Comma-separated targets to build (default: all).
                               Valid: linux-x86_64, linux-aarch64,
                                      mac-x86_64, mac-arm64
  -f, --force-download         Re-download cached archives even if present.
  -h, --help                   Show this message.

Downloaded archives are cached under .cache/download-toolchain/ keyed by
version, so re-running is cheap.
EOF
}

BUILD_MODDABLE_TOOLS=0
FORCE_DOWNLOAD=0
TARGETS_ARG=""
POSITIONAL=()
while [ $# -gt 0 ]; do
    case "$1" in
        --build-moddable-tools|-b) BUILD_MODDABLE_TOOLS=1; shift ;;
        --targets|-t) TARGETS_ARG="$2"; shift 2 ;;
        --targets=*) TARGETS_ARG="${1#*=}"; shift ;;
        --force-download|-f) FORCE_DOWNLOAD=1; shift ;;
        --help|-h) usage; exit 0 ;;
        --) shift; while [ $# -gt 0 ]; do POSITIONAL+=("$1"); shift; done ;;
        *) POSITIONAL+=("$1"); shift ;;
    esac
done
set -- "${POSITIONAL[@]}"

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

VERSION="${1:-14.2.1-1.1}"
# lin64 pulls the full tools bundle from $MODDABLE_VERSION, but overlays fontbm
# from $MODDABLE_VERSION_LIN64 because fontbm was dropped from lin64 builds
# after that version.
MODDABLE_VERSION="${2:-8.1.1}"
MODDABLE_VERSION_LIN64="5.7.0"

echo "Targets: ${TARGETS[*]}"
echo "xpack arm-none-eabi-gcc: $VERSION"
echo "Moddable SDK: $MODDABLE_VERSION (lin64 fontbm overlay: $MODDABLE_VERSION_LIN64)"
[ "$BUILD_MODDABLE_TOOLS" -eq 1 ] && echo "Build mode: building moddable-tools from ./moddable"

MODDABLE_BASE_URL="https://github.com/Moddable-OpenSource/moddable/releases/download/${MODDABLE_VERSION}"
MODDABLE_BASE_URL_LIN64_OLD="https://github.com/Moddable-OpenSource/moddable/releases/download/${MODDABLE_VERSION_LIN64}"
XPACK_BASE_URL="https://github.com/xpack-dev-tools/arm-none-eabi-gcc-xpack/releases/download/v${VERSION}"

CACHE_DIR=".cache/download-toolchain"
mkdir -p "$CACHE_DIR"

declare -A XPACK_SUFFIX=(
    [linux-x86_64]=linux-x64
    [linux-aarch64]=linux-arm64
    [mac-x86_64]=darwin-x64
    [mac-arm64]=darwin-arm64
)
declare -A MODDABLE_ZIP=(
    [linux-x86_64]=moddable-tools-lin64.zip
    [linux-aarch64]=moddable-tools-lin64arm.zip
    [mac-x86_64]=moddable-tools-mac64.zip
    [mac-arm64]=moddable-tools-mac64arm.zip
)
declare -A QEMU_ASSET=(
    [linux-x86_64]=qemu-pebble-linux-x86_64.tar.gz
    [linux-aarch64]=qemu-pebble-linux-arm64.tar.gz
    [mac-x86_64]=qemu-pebble-macos-x86_64.tar.gz
    [mac-arm64]=qemu-pebble-macos-arm64.tar.gz
)
declare -A DOCKER_PLATFORM=(
    [linux-x86_64]=linux/amd64
    [linux-aarch64]=linux/arm64
)

target_includes() {
    local t
    for t in "${TARGETS[@]}"; do [ "$t" = "$1" ] && return 0; done
    return 1
}

# Persistent cache: skip if file exists and non-empty unless --force-download.
download_cached() {
    local url="$1"
    local rel="$2"
    local dest="$CACHE_DIR/$rel"
    mkdir -p "$(dirname "$dest")"
    if [ "$FORCE_DOWNLOAD" -eq 0 ] && [ -s "$dest" ]; then
        echo "Cached: $rel"
        return
    fi
    echo "Downloading $rel..."
    curl -L --fail -o "$dest.tmp" "$url"
    mv "$dest.tmp" "$dest"
}

gh_download_cached() {
    local repo="$1" tag="$2" pattern="$3" rel_dir="$4"
    local dest="$CACHE_DIR/$rel_dir/$pattern"
    mkdir -p "$CACHE_DIR/$rel_dir"
    if [ "$FORCE_DOWNLOAD" -eq 0 ] && [ -s "$dest" ]; then
        echo "Cached: $rel_dir/$pattern"
        return
    fi
    echo "Downloading $pattern (from $repo $tag)..."
    gh release download "$tag" --repo "$repo" --pattern "$pattern" --dir "$CACHE_DIR/$rel_dir" --clobber
}

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

echo ""
echo "=== arm-none-eabi-gcc toolchain ==="
for target in "${TARGETS[@]}"; do
    file="xpack-arm-none-eabi-gcc-${VERSION}-${XPACK_SUFFIX[$target]}.tar.gz"
    download_cached "$XPACK_BASE_URL/$file" "xpack/$VERSION/$file"

    dir="toolchain-$target"
    rm -rf "$dir/arm-none-eabi"
    mkdir -p "$dir"

    extract_tmp=$(mktemp -d)
    tar --no-same-owner -xzf "$CACHE_DIR/xpack/$VERSION/$file" -C "$extract_tmp"
    mv "$extract_tmp/xpack-arm-none-eabi-gcc-${VERSION}" "$dir/arm-none-eabi"
    rm -rf "$extract_tmp"
    trim_arm_toolchain "$dir/arm-none-eabi"
    echo "Installed arm-none-eabi to $dir/arm-none-eabi/"
done

echo ""
echo "=== QEMU ==="
QEMU_RELEASE_TAG=$(gh release view --repo coredevices/qemu --json tagName --jq '.tagName')
echo "Using QEMU release: $QEMU_RELEASE_TAG"
for target in "${TARGETS[@]}"; do
    asset="${QEMU_ASSET[$target]}"
    gh_download_cached coredevices/qemu "$QEMU_RELEASE_TAG" "$asset" "qemu/$QEMU_RELEASE_TAG"

    dir="toolchain-$target"
    mkdir -p "$dir"
    tar --no-same-owner -xzf "$CACHE_DIR/qemu/$QEMU_RELEASE_TAG/$asset" -C "$dir"
    chmod +x "$dir/bin/qemu-pebble"
    echo "Installed qemu-pebble to $dir/bin/"
done

echo ""
echo "=== moddable-tools ==="
if [ "$BUILD_MODDABLE_TOOLS" -eq 1 ]; then
    if [ ! -d "moddable/build/makefiles" ]; then
        echo "Error: moddable submodule not initialized (moddable/build/makefiles missing)." >&2
        echo "Run: git submodule update --init --recursive" >&2
        exit 1
    fi

    for target in "${TARGETS[@]}"; do
        case "$target" in
            linux-*)
                platform="${DOCKER_PLATFORM[$target]}"
                tag="moddable-pebble-$target"
                echo "Building $target moddable-tools (docker $platform)..."
                docker build --platform "$platform" -f Dockerfile-moddable-tools -t "$tag" .
                rm -rf "toolchain-$target/moddable-tools"
                docker run --rm --platform "$platform" -v "$(pwd):/output" "$tag" \
                    sh -c "cp -r \$MODDABLE/build/bin/lin/release /output/toolchain-$target/moddable-tools && chown -R $(id -u):$(id -g) /output/toolchain-$target/moddable-tools"
                ;;
        esac
    done

    if target_includes mac-x86_64 || target_includes mac-arm64; then
        echo "Building mac universal moddable-tools (native)..."
        (
            export MODDABLE="$(pwd)/moddable"
            export PATH="${MODDABLE}/build/bin/mac/release:$PATH"
            export PLAT=macuniversal
            export MACOS_ARCH="-arch x86_64 -arch arm64"
            cd "${MODDABLE}/build/makefiles/mac"
            make
        )
        for target in mac-x86_64 mac-arm64; do
            if target_includes "$target"; then
                rm -rf "toolchain-$target/moddable-tools"
                cp -r "$(pwd)/moddable/build/bin/mac/release" "toolchain-$target/moddable-tools"
            fi
        done
    fi

    # Source builds don't produce fontbm — overlay it from prebuilt archives.
    # lin64 uses MODDABLE_VERSION_LIN64 because newer lin64 builds dropped fontbm.
    for target in "${TARGETS[@]}"; do
        if [ "$target" = "linux-x86_64" ]; then
            overlay_zip="moddable-tools-lin64.zip"
            overlay_url="$MODDABLE_BASE_URL_LIN64_OLD/$overlay_zip"
            overlay_rel="moddable/$MODDABLE_VERSION_LIN64/$overlay_zip"
        else
            overlay_zip="${MODDABLE_ZIP[$target]}"
            overlay_url="$MODDABLE_BASE_URL/$overlay_zip"
            overlay_rel="moddable/$MODDABLE_VERSION/$overlay_zip"
        fi
        download_cached "$overlay_url" "$overlay_rel"
        echo "Overlaying fontbm into toolchain-$target/moddable-tools..."
        unzip -o -j "$CACHE_DIR/$overlay_rel" fontbm -d "toolchain-$target/moddable-tools"
        chmod +x "toolchain-$target/moddable-tools/fontbm"
    done
else
    for target in "${TARGETS[@]}"; do
        zip="${MODDABLE_ZIP[$target]}"
        download_cached "$MODDABLE_BASE_URL/$zip" "moddable/$MODDABLE_VERSION/$zip"

        dir="toolchain-$target/moddable-tools"
        rm -rf "$dir"
        mkdir -p "$dir"
        unzip -o "$CACHE_DIR/moddable/$MODDABLE_VERSION/$zip" -d "$dir"
        find "$dir" -type f -exec chmod +x {} \;
        echo "Installed moddable-tools to $dir/"
    done

    # fontbm was dropped from lin64 builds after 5.7.0 — overlay from the older release.
    if target_includes linux-x86_64; then
        overlay_zip="moddable-tools-lin64.zip"
        overlay_rel="moddable/$MODDABLE_VERSION_LIN64/$overlay_zip"
        download_cached "$MODDABLE_BASE_URL_LIN64_OLD/$overlay_zip" "$overlay_rel"
        echo "Overlaying lin64 fontbm from Moddable SDK ${MODDABLE_VERSION_LIN64}..."
        unzip -o -j "$CACHE_DIR/$overlay_rel" fontbm -d "toolchain-linux-x86_64/moddable-tools"
        chmod +x "toolchain-linux-x86_64/moddable-tools/fontbm"
    fi
fi

echo ""
echo "Done! Targets installed: ${TARGETS[*]}"
