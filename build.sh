#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
APP="$PWD/build/澄控.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
make -C vendor/m1ddc CFLAGS='-Wall -Werror -Wextra -fmodules -fmodules-cache-path=/tmp/glasscontrol-clang-cache'
cp vendor/m1ddc/m1ddc "$APP/Contents/Helpers/m1ddc"
cp vendor/m1ddc/LICENSE "$APP/Contents/Resources/m1ddc-LICENSE.txt"
xcrun swiftc -swift-version 5 -O -module-cache-path /tmp/glasscontrol-swift-cache -target arm64-apple-macosx14.0 -sdk "$(xcrun --show-sdk-path)" Sources/main.swift -o "$APP/Contents/MacOS/GlassControl" -framework AppKit -framework SwiftUI -framework CoreAudio -framework ApplicationServices -framework ServiceManagement
cp Info.plist "$APP/Contents/Info.plist"
if [[ -f AppIcon.icns ]]; then cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"; fi
codesign --force --sign - "$APP/Contents/Helpers/m1ddc"
codesign --force --sign - "$APP"
"$APP/Contents/MacOS/GlassControl" --self-test
codesign --verify --deep --strict "$APP"
