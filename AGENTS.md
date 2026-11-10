# AGENTS.md

本文件为在这个仓库中工作的 AI 编码代理提供指引。

## 命令

- 全量测试:`swift test`(不需要签名)
- 单个测试:`swift test --filter 'WindowSearchTests/testEmptyQueryPreservesRecentOrder'`
- 快速自检:`swift build && .build/debug/OpenContexts --self-check`
- 本地打包:`SIGNING_MODE=adhoc ./scripts/build-app.sh`,然后 `open dist/OpenContexts.app`。默认的 `SIGNING_MODE=development` 在没有 Apple Development 证书,或有多张证书且未设 `CODE_SIGN_IDENTITY` 时会直接失败。
- 脚本测试:
  - `node scripts/test-website-search.cjs`
  - `python3 -B scripts/test-release-notes.py`
  - `python3 -B scripts/test-check-appcast.py`
- 官网预览:`python3 -m http.server 4173 --directory website`(官网没有构建步骤)
- Lint:`swiftformat Sources Tests --lint`(`--lint` 要放在路径后面;需要 `brew install swiftformat`;规则白名单在 `.swiftformat`,不在 CI 里)

## 架构

- 需要单测覆盖的逻辑放进 `OpenContextsCore`(不依赖 AppKit)。测试 target 只依赖 Core,`OpenContexts` 里的 AppKit、权限、键盘拦截和窗口管理只能靠 `--*-self-check` 和实机验证。
- 术语以 `CONTEXT.md` 为准。分组和排序的粒度是窗口,不是应用(`docs/adr/0002-window-granularity.md`)。
- `docs/requirements.md` 和 `docs/implementation-status.md` 是历史记录,不再维护。功能行为以 README 和代码为准。

## 提交与发版

- 直接提交到 `main`。
- 提交信息用英文 Conventional Commits 并带 scope,如 `feat(search): ...`、`fix(sidebar): ...`。
- CHANGELOG 在发版时集中写,功能提交不改 `CHANGELOG.md`。
- 发版:一个 `chore(release): prepare vX.Y.Z` 提交,只改 `CHANGELOG.md` 和 `VERSION`;在该提交上打附注 tag `vX.Y.Z` 并推送,由 `.github/workflows/release.yml` 完成构建、公证和发布。
- `VERSION` 是版本号的唯一来源,必须是稳定的 `x.y.z`,不接受 `1.2.3-beta` 这类版本。tag 必须等于 `v` 加 `VERSION`。
- CHANGELOG 版本段格式为 `## [x.y.z] - YYYY-MM-DD`,段内先英文(`### Added` 等)再中文(`### 新增` 等)。内容会原样进入 GitHub Release 和 Sparkle 更新窗口,要按面向用户的文字来写。

## 同步要求

- `README.md` 和 `README.zh-CN.md` 结构平行,改一份要同步另一份。
- `Sources/OpenContexts/Resources/` 下 en、es、fr、ja、zh 五份 `Localizable.strings` 的 key 集合必须相同且值非空。`swift test` 查不出这个问题,要跑 `--self-check`。
- `website/assets/site.js` 用 JS 重写了一份应用行为做演示,对应 `Sources/OpenContexts/AppController.swift` 和 `Panels.swift`。英文页在 `website/` 根路径,中文页在 `website/zh/` 下的对应路径。

## 容易踩的坑

- 没有 PR 或 push 时运行的测试 CI:`swift test` 只在发版时跑,`test-website-search.cjs` 不在任何 CI 里,改完要在本地跑。推送 `website/**` 到 `main` 会直接部署官网。
- 测试按字面内容切片源文件:
  - `scripts/test-website-search.cjs` 依赖 `site.js` 里的字面锚点,如 `    const toggleSidebar =`,改名或改缩进都会让测试失败。
  - `scripts/test-check-appcast.py` 依赖 `release.yml` 的步骤名 `Generate signed Sparkle appcast`。
- 未授权或应用退出时不得拦截 ⌘Tab。
- 辅助功能授权绑定签名身份、app identifier 和安装路径,重新签名可能丢失授权。不要随意改 bundle id `local.opencontexts.app`。
- `Info.plist` 由 `scripts/build-app.sh` 生成,仓库里没有 plist 文件。最低系统版本要同时改 `Package.swift` 和 `build-app.sh` 的 `LSMinimumSystemVersion`。
- Sparkle 在 `Package.swift` 里固定为精确版本,`build-app.sh` 写死了它的 artifacts 路径和 `Versions/B`,升级时要一起检查。
- `WindowSpaces.swift` 使用私有 API(dlopen 加载 SkyLight、`_AXUIElementCreateWithRemoteToken`),不支持时必须安全回退。
- `output/icon-candidates/` 里是未采用的候选图。发布用的图标在 `assets/`,README 截图在 `docs/screenshots/`。
