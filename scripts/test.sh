#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
swiftc -swift-version 5 -module-cache-path build/module-cache Sources/Core.swift Tests/CoreTests.swift -o build/core-tests
build/core-tests
swiftc -swift-version 5 -module-cache-path build/module-cache Sources/Core.swift Sources/OpenApplicationManager.swift Tests/OpenApplicationTests.swift -framework AppKit -o build/open-application-tests
build/open-application-tests
swiftc -swift-version 5 -module-cache-path build/module-cache Sources/AppLaunch.swift Tests/AppLaunchTests.swift -framework AppKit -o build/app-launch-tests
build/app-launch-tests
swiftc -swift-version 5 -module-cache-path build/module-cache Sources/LegacyLoginItem.swift Tests/LegacyLoginItemTests.swift -o build/legacy-login-tests
build/legacy-login-tests
