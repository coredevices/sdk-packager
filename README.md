# SDK Packager

A packager to generate the sdk tar.gz files that go on Cloudflare.

## Setup

Clone with submodules:
```shell
git clone --recurse-submodules https://github.com/coredevices/sdk-packager
```

Download (or build) the toolchains:
```shell
./download-toolchain.sh
```

Options:
- `-t, --targets <list>` — comma-separated subset of `linux-x86_64,linux-aarch64,mac-x86_64,mac-arm64` (default: all)
- `-b, --build-moddable-tools` — build moddable-tools from the `./moddable` submodule
- `-f, --force-download` — re-download cached archives
- positional args: `[xpack-version] [moddable-version]`

Archives are cached under `.cache/download-toolchain/` keyed by version.

## Usage

Build an SDK (requires `PEBBLEOS_PATH` pointing at a PebbleOS checkout with a configured `.venv`):
```shell
PEBBLEOS_PATH=../PebbleOS ./pack-sdk.sh $VERSION
```

Restrict the toolchain targets that get packed:
```shell
./pack-sdk.sh -t linux-x86_64,mac-arm64 $VERSION
```

Outputs land in `dist/releases/$VERSION/`.

Serve the dist tree locally:
```shell
python3 -m http.server -d dist/
```
