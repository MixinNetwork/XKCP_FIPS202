#!/bin/bash
set -euo pipefail

PROJECT_NAME="XKCP_FIPS202"
XKCP_DIR="XKCP"
TARBALL="$XKCP_DIR/bin/FIPS202-opt64.tar.gz"
BUILD_DIR="build"
OUTPUT_DIR="output"
IOS_VERSION_MIN="15.0"

rm -rf "$BUILD_DIR" "$OUTPUT_DIR"
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

pushd "$XKCP_DIR" > /dev/null
echo "Make FIPS202-opt64.pack..."
make FIPS202-opt64.pack
popd > /dev/null

SRC_DIR="$BUILD_DIR/src"
mkdir -p "$SRC_DIR"
tar -xzf "$TARBALL" -C "$SRC_DIR" --strip-components=1

build_arch() {
    ARCH=$1
    SDK=$2
    PLATFORM=$3

    echo "Building $PLATFORM ($ARCH)..."

    OBJ_DIR="$BUILD_DIR/obj_$PLATFORM"
    mkdir -p "$OBJ_DIR"
    if [[ "$SDK" == "iphonesimulator" ]]; then
        MIN_FLAG="-mios-simulator-version-min=$IOS_VERSION_MIN"
    else
        MIN_FLAG="-mios-version-min=$IOS_VERSION_MIN"
    fi
    
    for SRC_FILE in "$SRC_DIR"/*.c; do
        OBJ_FILE="$OBJ_DIR/$(basename "${SRC_FILE%.c}.o")"
        clang -arch "$ARCH" \
              -isysroot "$(xcrun --sdk $SDK --show-sdk-path)" \
              $MIN_FLAG \
              -Os \
              -I"$SRC_DIR" \
              -c "$SRC_FILE" \
              -o "$OBJ_FILE"
    done

    LIB_DIR="$BUILD_DIR/$PLATFORM"
    mkdir -p "$LIB_DIR"
    libtool -static -o "$LIB_DIR/$PROJECT_NAME" "$OBJ_DIR"/*.o

    rm -rf "$OBJ_DIR"
}

build_arch "arm64" "iphoneos" "ios-arm64"
build_arch "arm64" "iphonesimulator" "ios-arm64-simulator"

XCFRAMEWORK_DIR="$OUTPUT_DIR/$PROJECT_NAME.xcframework"

create_framework() {
    PLATFORM=$1
    LIB_DIR="$BUILD_DIR/$PLATFORM"
    FRAMEWORK_DIR="$XCFRAMEWORK_DIR/$PLATFORM/$PROJECT_NAME.framework"

    mkdir -p "$FRAMEWORK_DIR/Headers"
    mkdir -p "$FRAMEWORK_DIR/Modules"

    cp "$LIB_DIR/$PROJECT_NAME" "$FRAMEWORK_DIR/$PROJECT_NAME"
    cp "$SRC_DIR"/*.h "$FRAMEWORK_DIR/Headers/"

    cat > "$FRAMEWORK_DIR/Modules/module.modulemap" <<EOF
framework module "$PROJECT_NAME" {
    header "KeccakHash.h"
    header "SimpleFIPS202.h"

    export *
}
EOF
}

create_framework "ios-arm64"
create_framework "ios-arm64-simulator"

cat > "$XCFRAMEWORK_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AvailableLibraries</key>
	<array>
		<dict>
			<key>LibraryIdentifier</key>
			<string>ios-arm64</string>
			<key>LibraryPath</key>
			<string>${PROJECT_NAME}.framework</string>
			<key>SupportedArchitectures</key>
			<array>
				<string>arm64</string>
			</array>
			<key>SupportedPlatform</key>
			<string>ios</string>
		</dict>
		<dict>
			<key>LibraryIdentifier</key>
			<string>ios-arm64-simulator</string>
			<key>LibraryPath</key>
			<string>${PROJECT_NAME}.framework</string>
			<key>SupportedArchitectures</key>
			<array>
				<string>arm64</string>
			</array>
			<key>SupportedPlatform</key>
			<string>ios</string>
			<key>SupportedPlatformVariant</key>
			<string>simulator</string>
		</dict>
	</array>
	<key>CFBundlePackageType</key>
	<string>XFWK</string>
	<key>XCFrameworkFormatVersion</key>
	<string>1.0</string>
</dict>
</plist>
EOF

rm -rf "$BUILD_DIR"
echo "Finished"