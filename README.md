# AppWrapper

把**任意可执行文件连同它的依赖**打包成标准 macOS App Bundle（`.app`）的图形化工具，
启动脚本完全由你自己编写。中英双语界面。

Package **any executable together with its dependencies** into a standard macOS `.app`
bundle, with a fully user-editable launch script. Bilingual UI (中文 / English).

- [中文文档](#中文文档)
- [English Documentation](#english-documentation)

---

## 中文文档

### 功能特性

- **图形界面**：选择可执行文件、附加文件/文件夹、填写 App 信息、编辑启动脚本、一键打包
- **双语界面**：右上角切换 跟随系统 / 中文 / English，即时生效
- **自动收集依赖**：对 Mach-O 二进制用 `otool` 递归扫描动态库（支持 `@rpath` /
  `@loader_path` / `@executable_path` 解析），拷贝进 `Contents/Frameworks`
- **自动改写加载路径**：用 `install_name_tool` 把依赖引用改写为 `@rpath/...` 并添加
  指向包内 `Frameworks` 的 rpath；装载命令空间不足的旧二进制自动退化为由启动脚本里的
  `DYLD_FALLBACK_LIBRARY_PATH` 兜底
- **自定义启动脚本**：内置模板编辑器，占位符打包时自动替换
- **符号链接处理**：自动解析（如 `/opt/homebrew/bin/*` → Cellar 真实文件）
- **安全打包**：先在临时目录组装，成功后才替换旧 bundle；失败不会损坏已有产物
- **图标**：支持 `.icns`，或直接给一张 `.png`（自动用 sips + iconutil 转换）
- **ad-hoc 签名**：打包后自动签名，Apple Silicon 上可直接运行
- **CLI 模式**：`--cli config.json`，方便自动化 / CI

### 系统要求

- macOS 14+（Apple Silicon / Intel 均可）
- 构建本工具需要 Xcode 或 Command Line Tools（Swift 6）
- 运行时依赖系统自带的 `otool` / `install_name_tool` / `codesign` / `sips` / `iconutil`

### 构建与安装

```sh
git clone https://github.com/dotfrankruan/macos-app-wrapper.git
cd macos-app-wrapper

make            # release 构建 + 组装签名 AppWrapper.app
make run        # 构建并直接打开
make test       # 端到端 + 回归测试
make clean      # 清理
make help       # 查看全部目标
```

构建完成后把 `AppWrapper.app` 拖到 `/Applications`（或任意位置）即可。

> 沙箱等受限环境中 SwiftPM 需要 `--disable-sandbox` 与本地模块缓存，
> Makefile 已默认处理；正常终端环境可用 `make SWIFT_FLAGS=` 覆盖。

### 详细使用教程（GUI）

打开 AppWrapper 后，按界面上的 5 个分区操作：

**第 1 步 · 可执行文件**

点击「选择…」挑选要打包的程序：

- **Mach-O 二进制**（如 `/opt/homebrew/bin/ffmpeg`、自己编译的 C/Rust/Go 程序）：
  界面会显示 `Mach-O 二进制 — 将自动扫描动态库依赖`
- **脚本**（shell / python 等）：显示跳过依赖扫描的提示；脚本运行需要的东西
  （解释器数据、配置文件等）请在第 2 步手动添加

**第 2 步 · 附加文件 / 文件夹**

程序运行时需要的任何资源：数据文件、配置目录、JRE、资源包……
它们会被原样拷贝到 `MyApp.app/Contents/Resources/payload/` 下。
比如打包 Ghidra 时，把整个 `Ghidra` 目录加进来即可。

**第 3 步 · App 信息**

- **名称**：生成的 `.app` 文件名与显示名
- **Bundle ID**：反向域名格式，如 `com.example.myapp`
- **版本**：如 `1.0`
- **图标（可选）**：`.icns` 直接拷贝；`.png` 自动生成全套尺寸并转为 icns

**第 4 步 · 启动脚本（重点）**

这是最终 `.app` 的入口（`Contents/MacOS/<名称>`），可以完全重写。默认模板：

```zsh
#!/bin/zsh
# ============================================================
#  启动脚本 —— 由 AppWrapper 生成，可自由修改
#  可用变量:
#    APP_ROOT       指向 .app 的 Contents 目录
#    PAYLOAD_DIR    可执行文件与附加资源所在目录
#    FRAMEWORKS_DIR 自动收集的动态库依赖所在目录
# ============================================================
set -e

APP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PAYLOAD_DIR="$APP_ROOT/Resources/payload"
FRAMEWORKS_DIR="$APP_ROOT/Frameworks"

# 让动态链接器优先找到打包进来的依赖库
export DYLD_FALLBACK_LIBRARY_PATH="$FRAMEWORKS_DIR${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}"

# 如有需要，可在此导出其他环境变量，例如:
# export JAVA_HOME="$(/usr/libexec/java_home -v 21 2>/dev/null || true)"

cd "$PAYLOAD_DIR"
exec "$PAYLOAD_DIR/"{{SHELL_EXECUTABLE_NAME}} "$@"
```

两个占位符在打包时被替换：

| 占位符 | 替换为 | 用途 |
| --- | --- | --- |
| `{{SHELL_EXECUTABLE_NAME}}` | 带安全引用的主文件名（`'my app'`） | 推荐在脚本中使用 |
| `{{EXECUTABLE_NAME}}` | 原始主文件名（无引号） | 拼接路径等场景 |
| `{{APP_NAME}}` | App 名称 | 提示文案等 |

**示例：打包一个需要 JDK 21 的 Java 程序**（类似 Ghidra 的打包法）：

```zsh
#!/bin/zsh
set -e
APP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GHIDRA_HOME="$APP_ROOT/Resources/payload/Ghidra"

JAVA_HOME="$(/usr/libexec/java_home -v 21 2>/dev/null || true)"
if [[ -z "$JAVA_HOME" ]]; then
    osascript -e 'display alert "Ghidra requires JDK 21" message "No Java 21 found." as critical'
    exit 1
fi
export JAVA_HOME PATH="$JAVA_HOME/bin:/usr/bin:/bin"

cd "$GHIDRA_HOME"
exec "$GHIDRA_HOME/ghidraRun"
```

**第 5 步 · 打包选项与输出**

- **自动收集并打包动态库依赖**：默认开启
- **改写 install name / rpath**：默认开启；关掉则完全依赖启动脚本里的环境变量
- **ad-hoc 签名**：默认开启（Apple Silicon 上改动过加载路径的二进制必须重签才能运行）
- **输出目录**：生成 `<名称>.app` 的位置

点击 **「开始打包 .app」**，日志区实时显示每一步；完成后自动在访达中选中产物。

### CLI 模式（自动化 / CI）

```sh
./AppWrapper.app/Contents/MacOS/AppWrapper --cli config.json [--lang zh|en]
```

`config.json` 完整字段：

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `executable` | ✅ | 主可执行文件路径（符号链接会自动解析） |
| `appName` | ✅ | App 名称 |
| `additionalItems` | | 附加文件/文件夹路径数组 |
| `bundleID` | | 默认 `com.example.<appname>` |
| `version` | | 默认 `"1.0"` |
| `icon` | | `.icns` 或 `.png` 路径 |
| `script` | | 内联启动脚本（字符串） |
| `scriptFile` | | 从文件读取启动脚本（优先于 `script`） |
| `copyDependencies` | | 默认 `true` |
| `fixInstallNames` | | 默认 `true` |
| `adhocSign` | | 默认 `true` |
| `outputDirectory` | | 默认当前目录 |

示例（打包 ffmpeg 及其全部依赖，实测生成 19 个库的独立 bundle）：

```json
{
  "executable": "/opt/homebrew/bin/ffmpeg",
  "appName": "FFmpeg",
  "bundleID": "com.example.ffmpeg",
  "outputDirectory": "/tmp/out"
}
```

### 生成的 bundle 结构

```
MyApp.app/
└── Contents/
    ├── Info.plist            # 由 App 信息生成
    ├── MacOS/
    │   └── MyApp             # 你的启动脚本（可执行）
    ├── Resources/
    │   ├── AppIcon.icns      # 可选
    │   └── payload/          # 主可执行文件 + 附加文件/文件夹
    └── Frameworks/           # 自动收集的动态库依赖
```

### 常见问题

- **双击提示“已损坏/无法验证开发者”**：产物是 ad-hoc 签名的本地应用，
  首次打开请在「系统设置 → 隐私与安全性」中允许，或执行
  `xattr -dr com.apple.quarantine MyApp.app`
- **日志提示 “no room for a new rpath”**：该二进制链接时未预留 headerpad，
  无法注入 rpath；AppWrapper 会自动退化为 `DYLD_FALLBACK_LIBRARY_PATH` 方案，不影响使用
- **某些依赖显示“无法解析”**：它们是运行时按需加载（dlopen）或位于非标准路径，
  可用「附加文件」手动带上，并在启动脚本里设置相应环境变量
- **脚本类程序**（Python 等）：AppWrapper 不会打包解释器本身；
  可用附加文件带上 venv/依赖目录，并在启动脚本里指向系统或随包解释器

### 测试

```sh
make test   # 端到端（dylib 打包 + 隐藏源目录后运行产物）+ Python 回归（注入/回滚/占位符等）
```

---

## English Documentation

### Features

- **GUI**: pick an executable, extra files/folders, app metadata, edit the launch script, one-click packaging
- **Bilingual UI**: 中文 / English / follow-system, switchable live from the top-right picker
- **Automatic dependency collection**: recursive `otool` scan of Mach-O binaries
  (`@rpath` / `@loader_path` / `@executable_path` resolution) into `Contents/Frameworks`
- **Load path rewriting**: `install_name_tool` rewrites references to `@rpath/...` and adds
  rpaths to the bundled `Frameworks`; binaries without headerpad space automatically fall
  back to `DYLD_FALLBACK_LIBRARY_PATH` exported by the launch script
- **Fully editable launch script** with a built-in template and placeholders
- **Symlink resolution** (e.g. `/opt/homebrew/bin/*` → real Cellar files)
- **Safe packaging**: assembles in a staging directory and only replaces an existing bundle
  on success, so a failed build never corrupts the previous product
- **Icons**: `.icns` directly, or a `.png` auto-converted via sips + iconutil
- **Ad-hoc codesigning** so binaries run on Apple Silicon
- **CLI mode**: `--cli config.json` for automation / CI

### Requirements

- macOS 14+ (Apple Silicon or Intel)
- Xcode or Command Line Tools (Swift 6) to build
- Uses system `otool`, `install_name_tool`, `codesign`, `sips`, `iconutil` at runtime

### Build

```sh
git clone https://github.com/dotfrankruan/macos-app-wrapper.git
cd macos-app-wrapper

make            # release build + assemble & sign AppWrapper.app
make run        # build and launch the GUI
make test       # end-to-end + regression tests
make clean      # clean artifacts
make help       # list all targets
```

Then drag `AppWrapper.app` to `/Applications` (or anywhere).

### GUI Walkthrough

The window is organized into 5 numbered sections:

**1. Executable** — Choose the program to package:

- **Mach-O binaries** (e.g. `/opt/homebrew/bin/ffmpeg`, your own C/Rust/Go builds):
  dependencies are scanned automatically
- **Scripts** (shell/python/…): dependency scanning is skipped; add everything the
  script needs in section 2

**2. Additional Files / Folders** — Anything the program needs at runtime: data files,
config directories, a JRE, resource bundles… copied verbatim into
`MyApp.app/Contents/Resources/payload/`.

**3. App Info** — Name (becomes the `.app` file name), Bundle ID, Version, optional Icon
(`.icns` or `.png`).

**4. Launch Script** — The entry point of the final `.app`
(`Contents/MacOS/<Name>`), fully editable. Default template:

```zsh
#!/bin/zsh
# ============================================================
#  Launch script — generated by AppWrapper, edit freely
#  Available variables:
#    APP_ROOT       the .app's Contents directory
#    PAYLOAD_DIR    the executable and bundled resources
#    FRAMEWORKS_DIR auto-collected dynamic libraries
# ============================================================
set -e

APP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PAYLOAD_DIR="$APP_ROOT/Resources/payload"
FRAMEWORKS_DIR="$APP_ROOT/Frameworks"

# Let dyld find the bundled libraries first
export DYLD_FALLBACK_LIBRARY_PATH="$FRAMEWORKS_DIR${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}"

# Export any other environment variables you need, e.g.:
# export JAVA_HOME="$(/usr/libexec/java_home -v 21 2>/dev/null || true)"

cd "$PAYLOAD_DIR"
exec "$PAYLOAD_DIR/"{{SHELL_EXECUTABLE_NAME}} "$@"
```

Placeholders replaced at build time:

| Placeholder | Replaced with | Use |
| --- | --- | --- |
| `{{SHELL_EXECUTABLE_NAME}}` | safely shell-quoted main file name | recommended in scripts |
| `{{EXECUTABLE_NAME}}` | raw main file name (unquoted) | path building, etc. |
| `{{APP_NAME}}` | the app name | messages, etc. |

**5. Options & Output** — dependency collection (on), install-name rewriting (on),
ad-hoc signing (on), and the output folder. Click **Build .app**; the log pane shows every
step and Finder reveals the result when finished.

### CLI Mode

```sh
./AppWrapper.app/Contents/MacOS/AppWrapper --cli config.json [--lang zh|en]
```

| Field | Required | Description |
| --- | --- | --- |
| `executable` | ✅ | path to the main executable (symlinks are resolved) |
| `appName` | ✅ | app name |
| `additionalItems` | | array of extra file/folder paths |
| `bundleID` | | defaults to `com.example.<appname>` |
| `version` | | defaults to `"1.0"` |
| `icon` | | path to `.icns` or `.png` |
| `script` | | inline launch script (string) |
| `scriptFile` | | read launch script from file (wins over `script`) |
| `copyDependencies` | | default `true` |
| `fixInstallNames` | | default `true` |
| `adhocSign` | | default `true` |
| `outputDirectory` | | defaults to the current directory |

### Generated Bundle Layout

```
MyApp.app/
└── Contents/
    ├── Info.plist            # generated from the app metadata
    ├── MacOS/
    │   └── MyApp             # your launch script (executable)
    ├── Resources/
    │   ├── AppIcon.icns      # optional
    │   └── payload/          # main executable + additional files/folders
    └── Frameworks/           # auto-collected dynamic libraries
```

### FAQ

- **“Damaged” / “unidentified developer” on first launch**: the product is ad-hoc signed.
  Allow it in System Settings → Privacy & Security, or run
  `xattr -dr com.apple.quarantine MyApp.app`
- **“no room for a new rpath” in the log**: the binary was linked without headerpad;
  AppWrapper falls back to `DYLD_FALLBACK_LIBRARY_PATH` automatically — nothing to do
- **“Unresolved dependency” warnings**: those libraries are usually dlopen'ed at runtime
  or live in non-standard paths; ship them via Additional Files and set the appropriate
  environment variables in your launch script
- **Script-based programs** (Python etc.): the interpreter itself is not bundled; ship a
  venv/dependencies via Additional Files and point your script at a system or bundled
  interpreter

### Acknowledgements

The bundle layout and launch-script style are inspired by a hand-packaged `Ghidra.app`
(a zsh launcher in `Contents/MacOS`, the payload in `Contents/Resources`).

### License

[Apache License 2.0](LICENSE)
