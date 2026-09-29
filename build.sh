#!/bin/zsh
# 构建 AppWrapper 自身的 .app（需要 Xcode / Command Line Tools）
set -e
cd "$(dirname "$0")"

# 在某些受限环境（如沙箱）中需要重定向模块缓存；正常情况下无副作用
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH"

echo "==> swift build -c release"
swift build -c release --disable-sandbox

APP="AppWrapper.app"
echo "==> 组装 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/AppWrapper "$APP/Contents/MacOS/AppWrapper"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

echo "==> ad-hoc 签名"
codesign --force --deep --sign - "$APP" 2>/dev/null || \
  codesign --force --sign - "$APP" || true

echo "==> 完成: $PWD/$APP"
