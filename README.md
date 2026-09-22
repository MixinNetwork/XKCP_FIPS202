Build XKCP to an XCFramework using FIPS202-opt64. Requires macOS with Xcode
and its iOS SDKs installed.

```bash
git clone --recurse-submodules git@github.com:MixinNetwork/XKCP_FIPS202.git
chmod +x ./build_xcframework.sh
./build_xcframework.sh
```

The script produces `output/XKCP_FIPS202.xcframework` with only arm64 iOS
device and arm64 iOS Simulator slices, both targeting iOS 15.0. Builds always
use Release optimization (`-O3` and `NDEBUG`).

The XCFramework contains static libraries (`libXKCP_FIPS202.a`), with headers
and a Clang module map under `Headers/XKCP_FIPS202/` in each slice. It is ready
for a Swift package binary target without repackaging:

```swift
.binaryTarget(
    name: "XKCP_FIPS202",
    path: "XKCP_FIPS202.xcframework",
)
```

Copy the generated XCFramework into that path in the consuming package. Add
`"XKCP_FIPS202"` to the consuming target's dependencies, then use
`import XKCP_FIPS202`. The namespaced headers avoid collisions with other
binary packages, and the static library is linked without embedding a framework.
