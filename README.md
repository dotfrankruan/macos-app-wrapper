# AppWrapper — 可执行文件打包为 macOS .app 的图形工具

用 SwiftUI 编写的小工具：把**任意可执行文件连同它的依赖**打包成一个标准的
macOS App Bundle（`.app`）。启动脚本完全由用户自己编写。

## 功能

- **图形界面**：选择可执行文件、附加文件/文件夹、填写 App 信息、编辑启动脚本、一键打包
- **自动收集依赖**：对 Mach-O 二进制用 `otool` 递归扫描动态库（支持 `@rpath` /
  `@loader_path` / `@executable_path` 解析），拷贝进 `Contents/Frameworks`
- **自动改写加载路径**：用 `install_name_tool` 把依赖引用改写为 `@rpath/...` 并添加
  指向包内 `Frameworks` 的 rpath；空间不足的二进制由启动脚本里的
  `DYLD_FALLBACK_LIBRARY_PATH` 兜底
- **自定义启动脚本**：脚本编辑器自带模板，`{{EXECUTABLE_NAME}}` 占位符在打包时
  自动替换为主文件名。脚本最终成为 `Contents/MacOS/<启动器>`
- **图标**：支持 `.icns`，或直接给一张 `.png`（自动用 sips + iconutil 转换）
- **ad-hoc 签名**：打包后自动签名，Apple Silicon 上可直接运行
- **CLI 模式**：`AppWrapper --cli config.json`，方便自动化/CI

## 生成的 bundle 结构

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

## 构建本工具

需要 Xcode（或 Command Line Tools）与 Swift 6：

```sh
make            # 等价于 make app：release 构建 + 组装签名 AppWrapper.app
make run        # 构建并打开图形界面
make test       # 端到端测试：打包一个带 dylib 依赖的 C 程序并校验输出
make clean      # 清理
make help       # 全部目标
```

也可以用脚本：`./build.sh`。或者直接跑源码：

```sh
swift run --disable-sandbox AppWrapper
```

## 使用方法（GUI）

1. **可执行文件**：选择要打包的程序（Mach-O 二进制会自动扫描依赖；脚本也可以）
2. **附加文件**：程序运行需要的数据文件、配置、JRE 等，原样拷进 `Resources/payload`
3. **App 信息**：名称 / Bundle ID / 版本 / 图标
4. **启动脚本**：在模板基础上自行修改。可用环境：
   - `APP_ROOT` → `.app/Contents`
   - `PAYLOAD_DIR` → `.app/Contents/Resources/payload`
   - `FRAMEWORKS_DIR` → `.app/Contents/Frameworks`
5. **选项**：依赖收集 / 改写 install name / ad-hoc 签名 / 输出目录
6. 点击 **开始打包 .app**

## CLI 模式

```sh
./AppWrapper.app/Contents/MacOS/AppWrapper --cli config.json
```

```json
{
  "executable": "/opt/homebrew/bin/ffmpeg",
  "additionalItems": ["/path/to/data"],
  "appName": "FFmpeg",
  "bundleID": "com.example.ffmpeg",
  "version": "1.0",
  "icon": "/path/icon.png",
  "copyDependencies": true,
  "fixInstallNames": true,
  "adhocSign": true,
  "outputDirectory": "/tmp/out"
}
```

`script`（内联文本）或 `scriptFile`（脚本路径）可覆盖默认启动脚本模板。

## 参考

bundle 布局与启动脚本风格参考了 `Ghidra.app` 的手工打包方式
（`Contents/MacOS` 放 zsh 启动脚本，程序本体放 `Contents/Resources`）。
