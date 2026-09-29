# ============================================================
# AppWrapper — 把任意可执行文件连同依赖打包成 macOS .app
# ============================================================

APP        := AppWrapper.app
BIN        := .build/release/AppWrapper
DEBUG_BIN  := .build/debug/AppWrapper

# 在沙箱等受限环境中需要重定向模块缓存；普通环境无副作用
export CLANG_MODULE_CACHE_PATH     := $(CURDIR)/.build/module-cache
export SWIFTPM_MODULECACHE_OVERRIDE := $(CURDIR)/.build/module-cache

# SwiftPM 沙箱在部分环境（如本仓库的开发沙箱）中无法嵌套，默认关闭；
# 正常环境可用 `make SWIFT_FLAGS=` 覆盖
SWIFT_FLAGS ?= --disable-sandbox

TEST_DIR   := .test-tmp

.PHONY: all debug release app run test clean help

all: app          ## 构建 release 并组装 AppWrapper.app（默认目标）

help:             ## 显示帮助
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  make %-10s %s\n", $$1, $$2}'

debug:            ## 构建 debug 版本
	swift build $(SWIFT_FLAGS)

release:          ## 构建 release 版本
	swift build -c release $(SWIFT_FLAGS)

app: release      ## 组装并签名 AppWrapper.app
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp "$(BIN)" "$(APP)/Contents/MacOS/AppWrapper"
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	@if [ -f Resources/AppIcon.icns ]; then \
	  cp Resources/AppIcon.icns "$(APP)/Contents/Resources/AppIcon.icns"; \
	fi
	codesign --force --deep --sign - "$(APP)" 2>/dev/null || \
	  codesign --force --sign - "$(APP)" || true
	@echo "==> 完成: $(CURDIR)/$(APP)"

run: app          ## 构建并打开图形界面
	open "$(APP)"

test: debug       ## 端到端测试：打包一个带 dylib 依赖的 C 程序并验证运行
	@echo "==> 准备测试程序"
	@rm -rf "$(TEST_DIR)" && mkdir -p "$(TEST_DIR)/src" "$(TEST_DIR)/out"
	@echo 'const char* foo_message(void) { return "hello from bundled libfoo"; }' \
	  > "$(TEST_DIR)/src/foo.c"
	@printf '%s\n' \
	  '#include <stdio.h>' \
	  'extern const char* foo_message(void);' \
	  'int main(void) { printf("%s\n", foo_message()); return 0; }' \
	  > "$(TEST_DIR)/src/main.c"
	clang -dynamiclib "$(TEST_DIR)/src/foo.c" -o "$(TEST_DIR)/src/libfoo.dylib" \
	  -install_name @rpath/libfoo.dylib
	clang "$(TEST_DIR)/src/main.c" -o "$(TEST_DIR)/src/hello" \
	  -L"$(TEST_DIR)/src" -lfoo -Wl,-rpath,@executable_path
	@echo "==> 用 CLI 模式打包"
	@printf '%s\n' \
	  '{' \
	  '  "executable": "$(CURDIR)/$(TEST_DIR)/src/hello",' \
	  '  "appName": "HelloTest",' \
	  '  "bundleID": "com.example.hellotest",' \
	  '  "outputDirectory": "$(CURDIR)/$(TEST_DIR)/out"' \
	  '}' > "$(TEST_DIR)/config.json"
	"$(DEBUG_BIN)" --cli "$(TEST_DIR)/config.json"
	@echo "==> 运行打包产物并校验输出"
	@OUTPUT=$$("$(TEST_DIR)/out/HelloTest.app/Contents/MacOS/HelloTest"); \
	echo "    输出: $$OUTPUT"; \
	test "$$OUTPUT" = "hello from bundled libfoo" \
	  && echo "==> ✅ 端到端测试通过" \
	  || { echo "==> ❌ 测试失败"; exit 1; }

clean:            ## 清理构建产物与测试文件
	rm -rf .build "$(TEST_DIR)" "$(APP)"
