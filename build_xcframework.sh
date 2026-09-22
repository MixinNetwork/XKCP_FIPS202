#!/bin/bash
# Build FIPS202-opt64 in Release mode for arm64 iOS devices and simulators.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XKCP_DIR="$ROOT_DIR/XKCP"
NAME="XKCP_FIPS202"
DEPLOYMENT_TARGET="15.0"
OUTPUT_DIR="$ROOT_DIR/output"

if [[ "$(uname -s)" != Darwin ]]; then
    echo "error: macOS with Xcode and the iOS SDKs is required." >&2
    exit 1
fi

for tool in xcodebuild xcrun make xsltproc; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "error: required tool '$tool' was not found." >&2
        exit 1
    fi
done

if [[ ! -f "$XKCP_DIR/support/XKCBuild/src/Main.makefile" ]]; then
    echo "error: initialize the submodules with: git submodule update --init --recursive" >&2
    exit 1
fi

# Resolve both SDKs before generating any build products.
DEVICE_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
SIMULATOR_SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
CLANG="$(xcrun --find clang)"
LIBTOOL="$(xcrun --find libtool)"

mkdir -p "$ROOT_DIR/build/Release" "$OUTPUT_DIR"
BUILD_DIR="$(mktemp -d "$ROOT_DIR/build/Release/xcframework.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT

# Force regeneration so an old source archive or generated config cannot be reused.
make -C "$XKCP_DIR" -B FIPS202-opt64.pack
tar -xzf "$XKCP_DIR/bin/FIPS202-opt64.tar.gz" -C "$BUILD_DIR"
SOURCE_DIR="$BUILD_DIR/FIPS202-opt64"
# The upstream pack omits this dependency of SnP-implementations.c.
cp "$XKCP_DIR/lib/common/PlSnP-common.h" "$SOURCE_DIR/"

build_library() {
    local sdk_name="$1" sdk_path="$2" target="$3"
    local slice_dir="$BUILD_DIR/$sdk_name"
    local headers="$slice_dir/Headers/$NAME"
    local source
    mkdir -p "$slice_dir/objects" "$headers"

    echo "Building Release: $sdk_name (arm64, iOS $DEPLOYMENT_TARGET)"
    for source in "$SOURCE_DIR"/*.c; do
        "$CLANG" -target "$target" -isysroot "$sdk_path" \
            -O3 -DNDEBUG -std=c99 -fPIC -I "$SOURCE_DIR" \
            -c "$source" -o "$slice_dir/objects/$(basename "${source%.c}").o"
    done
    "$LIBTOOL" -static -o "$slice_dir/lib$NAME.a" "$slice_dir/objects/"*.o
    cp "$SOURCE_DIR/"*.h "$headers/"

    # Namespace the headers and module map: Xcode copies static XCFramework
    # headers into a shared include directory alongside other packages.
    cat > "$headers/module.modulemap" <<EOF
module $NAME {
    header "KeccakHash.h"
    header "SimpleFIPS202.h"
    export *
}
EOF
}

build_library iphoneos "$DEVICE_SDK" "arm64-apple-ios$DEPLOYMENT_TARGET"
build_library iphonesimulator "$SIMULATOR_SDK" "arm64-apple-ios$DEPLOYMENT_TARGET-simulator"

# Raw static libraries are linked by SPM without embedding framework bundles.
xcodebuild -create-xcframework \
    -library "$BUILD_DIR/iphoneos/lib$NAME.a" \
    -headers "$BUILD_DIR/iphoneos/Headers" \
    -library "$BUILD_DIR/iphonesimulator/lib$NAME.a" \
    -headers "$BUILD_DIR/iphonesimulator/Headers" \
    -output "$BUILD_DIR/$NAME.xcframework"

# Only replace the previous output after both slices have been packaged successfully.
rm -rf "$OUTPUT_DIR/$NAME.xcframework"
mv "$BUILD_DIR/$NAME.xcframework" "$OUTPUT_DIR/"
echo "Built $OUTPUT_DIR/$NAME.xcframework"
