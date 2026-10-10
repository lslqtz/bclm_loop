#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/bclm-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
test_platform="$(xcrun --sdk macosx --show-sdk-platform-path)/Developer"
cp Tests/FirmwareLimitTests.swift "$test_dir/main.swift"
xcrun --sdk macosx swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" -module-cache-path "$test_dir/modules" \
    -I "$test_platform/usr/lib" -L "$test_platform/usr/lib" \
    -F "$test_platform/Library/Frameworks" \
    -Xlinker -rpath -Xlinker "$test_platform/Library/Frameworks" \
    -Xlinker -rpath -Xlinker "$test_platform/usr/lib" \
    -Xlinker -rpath -Xlinker "$(xcode-select -p)/Library/PrivateFrameworks" \
    -Xlinker -rpath -Xlinker "$(xcode-select -p)/../SharedFrameworks" \
    Sources/bclm_loop/SMC.swift Sources/bclm_loop/FirmwareLimit.swift \
    "$test_dir/main.swift" -o "$test_dir/tests"
"$test_dir/tests"
