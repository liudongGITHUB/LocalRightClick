# 轻右键 · LocalRightClick

免费的 macOS 原生 Finder 右键工具，支持新建文件、在应用中打开、拷贝路径、复制/移动文件和常用目录。日常文件操作无需联网，没有广告、账号或第三方运行时依赖。

## 下载与安装

支持 **macOS 12 及以上**，同一个安装包兼容 **Intel 和 Apple Silicon（M 系列）Mac**。

前往 **[下载页面（Releases）](https://github.com/liudongGITHUB/LocalRightClick/releases/latest)** 下载最新版本：

- **`LocalRightClick-版本号-universal.pkg`**：推荐，双击后按中文向导安装到“应用程序”。
- **`LocalRightClick-版本号-universal.zip`**：解压后将“轻右键.app”拖入“应用程序”。
- `SHA256SUMS.txt`：安装包校验值。GitHub 自动生成的 Source code 是源码，不是可直接运行的应用。

更新前请退出轻右键，等待文件复制/移动操作完成。安装会保留个人配置和自定义模板。

安装后打开轻右键，在 **通用设置 → 管理扩展…** 中启用 Finder 扩展。看到“右键扩展已启用”后，重新打开访达右键菜单。

更新后若菜单未出现或仍显示旧内容，在系统扩展设置中将“轻右键”关闭再开启一次。

### 软件内手动更新

从 1.1.2 开始，在 **通用设置 → 软件更新 → 检查更新** 中查看 GitHub 正式发布版本。发现新版后可查看更新说明并下载；安装包通过 SHA-256 校验后，点击“退出并安装…”打开系统安装向导，完成覆盖更新。正在执行文件操作时不会退出安装；已有配置和模板会保留。

安装向导仍需手动完成，系统可能要求管理员密码或首次打开确认。1.1.1 及更早版本需要先从 Releases 手动下载安装一次。此功能不会在后台自动检查或安装；网络失败、GitHub 限流或校验失败时会提示重试。

### 首次打开的系统提示

当前发布版本采用本机 ad-hoc 签名，**没有 Apple Developer ID 签名和公证**，因此 macOS 可能拦截安装包或应用。如果确认下载自本仓库，可按照 [Apple 官方说明](https://support.apple.com/zh-cn/102445) 在系统的安全设置中允许打开：

- macOS 12：系统偏好设置 → 安全性与隐私 → 通用。
- macOS 13 及以上：系统设置 → 隐私与安全性。

无需关闭 Gatekeeper、SIP 或全局安全保护。受组织管理的电脑可能不允许安装未经公证的应用。

## 功能

| 功能 | 用法 |
| --- | --- |
| 新建文件 | 内置 23 种模板，包含 TXT、Markdown、JSON、Office、CSV、XML、HTML 和常见代码格式 |
| 主菜单快捷新建 | 在“新建文件”页同时勾选“启用”和“主菜单”，直接在右键第一层显示；其余位于“轻右键 → 新建文件” |
| 自定义模板 | 新建文本模板或导入真实文件，支持启用、排序、修改显示名称和默认文件名 |
| 在此打开 | 添加本机应用，启用/停用、排序或移除；默认包含终端、iTerm、VS Code 和 Cursor |
| 拷贝路径 | 选中一个或多个项目，按行复制完整路径 |
| 复制到 / 移动到 | 选择目录或常用目录；拒绝覆盖同名文件，移动前确认 |
| 常用目录 | 快速跳转，也可用作文件复制/移动目标 |
| 登录时启动 | 可选；不开启时右键操作仍会按需唤起主应用 |

设置自动保存，重新打开右键菜单即生效。移除应用只移除菜单配置，不卸载软件。

### 文件模板

内置 TXT、Markdown、JSON、Word、Excel、PowerPoint、RTF、CSV、XML、HTML、YAML、Python、Shell、JavaScript、TypeScript、CSS、SQL、TOML、INI、TSV、SVG、Swift 和 Java；默认启用前 10 种。

Word/Excel/PowerPoint 使用有效的空白 Office 文档。WPS、iWork、AI、PSD 等专用格式可导入对应软件生成的真实模板：支持 20 MB 以内普通文件，以及 Pages/Numbers/Keynote 文稿包。导入后保存独立副本，不修改原文件。创建脚本文件只写入内容，不执行脚本。

选中单个文件夹时在该目录创建；选中文件时在其所在目录创建；空白处右键则在当前目录创建。文档图标跟随本机的文件类型关联。

点击文件类型后直接创建，不弹出命名确认窗口；使用设置页中的“默认文件名”。同名时自动加序号，例如“新建文本文档 2.txt”，不覆盖已有文件。创建后在访达中选中新文件，可按回车重命名。

### 登录时启动

在 **通用设置 → 登录时启动** 中启用。登录后在菜单栏运行，不主动弹出设置；手动打开应用仍显示设置窗口。

macOS 13+ 使用系统登录项；macOS 12 使用用户级 LaunchAgent，在下次登录时启动。两者均可通过应用内开关关闭。此设置按电脑和用户独立配置，不随安装包转移。

## 隐私、权限与限制

- 无账号或遥测。配置、模板和短时动作请求保存在本机 `~/Library/Application Support/LocalRightClick/`。
- 仅手动检查或下载更新时访问 GitHub 仓库及下载服务，不上传个人配置、模板或文件。检查更新读取 Release 的 `update.json` 清单，不依赖 GitHub API 配额。SHA-256 用于检查下载完整性，不替代 Apple 开发者签名或公证。
- Finder 扩展运行于沙箱，例外访问范围仅为上述目录；主应用以当前用户身份执行文件操作。
- 操作“文稿”“桌面”“下载”等保护目录时，macOS 可能询问访问权限。无需辅助功能或完全磁盘访问权限。
- 扩展覆盖个人目录、`/Volumes` 和 `/private/tmp`。iCloud/File Provider 管理的位置可能不显示 Finder Sync 菜单，暂未提供服务菜单兜底。
- 文件批量操作逐项执行。权限、磁盘断开或空间不足会报告失败；失败复制可能留下不完整副本，不自动回滚或删除用户文件。
- 目标应用支持哪些文件或目录由该应用决定。
- 已进行双架构编译和最低系统版本检查；**macOS 12 真机、Intel Mac 的完整安装和登录启动流程尚未验收**。

## 从源码构建

需要 macOS、Command Line Tools（`swiftc`、Python 3 和打包工具）。无第三方库依赖。

在仓库根目录运行：

```bash
bash scripts/test.sh
bash scripts/build.sh
bash scripts/package.sh
```

应用位于 `build/轻右键.app`，PKG 位于 `build/packages/`。无需先安装到本机即可打包。

生成可发布的 PKG、ZIP 和 SHA-256 校验文件：

```bash
bash scripts/release.sh
```

输出到 `build/release/版本号/`。开发时如需更新本机应用，退出旧版后运行 `bash scripts/install.sh`；脚本会归档旧版与构建副本，避免重复应用。

## 自动构建与发布

GitHub Actions 在推送和 Pull Request 时运行测试、构建通用版并检查安装包。推送与应用版本一致的标签（例如 `v1.1.2`）后，工作流发布 GitHub Release，并附上 PKG、ZIP、SHA-256 校验值和 `update.json` 更新清单。手动发布时也必须上传这四个文件。普通 CI 没有发布权限。

## 配置与卸载

配置和模板目录：`~/Library/Application Support/LocalRightClick/`，可通过通用设置中的“打开配置目录”访问。

卸载前关闭“登录时启动”，等待文件任务完成并退出应用，在系统设置中停用 Finder 扩展，再将“轻右键.app”移到废纸篓。个人配置不会自动删除；如不再需要，可自行移除上述配置目录。

## 许可与反馈

采用 [MIT 许可](LICENSE)。应用图标由 AI 生成，说明见 [Resources/README.md](Resources/README.md)。内置 Office 模板独立生成，未复用第三方付费软件代码或资源。

欢迎通过 Issues 报告问题，请注明 macOS 版本、芯片类型、软件版本和复现步骤。不要提交个人文件、完整配置或凭据。
