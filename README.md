# SDK Packager

A packager to generate the sdk tar.gz files that go on Cloudflare.

#### Clone this repo
```shell
git clone --recurse-submodules https://github.com/coredevices/sdk-packager
```

#### Download the toolchains

```shell
./download-toolchain.sh
```

# Usage

Build an sdk
```shell
./pack-sdk.sh $VERSION
```

Run locally
```shell
python3 -m http.server -d dist/
```

Override SDK server (requires a matching manifest in dist/v1/files/sdk-core)
```shell
PEBBLE_SDK_SERVER=http://localhost:8000 pebble sdk install $VERSION
```
