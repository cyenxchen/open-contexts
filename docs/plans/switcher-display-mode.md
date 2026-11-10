# 窗口切换器显示位置设置:实现文档

## 目标

在设置 → General 新增一个选项,让用户决定多显示器时窗口切换器(`SwitcherPanel`)的显示位置:

- **所有显示器**(`allDisplays`,默认):和当前行为一致,每块屏幕都显示一份切换器。
- **主显示器**(`primaryDisplay`):只在主显示器上显示。

## 现状

- `AppController.rebuildPanels()`(`Sources/OpenContexts/AppController.swift:121`)给 `NSScreen.screens` 的每块屏幕各建一个 `SwitcherPanel`,存在 `switchers: [CGDirectDisplayID: SwitcherPanel]`。
- 所有显示和刷新都遍历 `switchers.values`:
  - `rebuildPanels()` 末尾,切换中重建时重新 `show`(第 154-160 行)
  - `handle(.begin)` 的 `show`(第 220-224 行)
  - `updateSwitchers(resetHover:)` 的 `update`(第 281-287 行)
  - `finishSwitcher` 的 `hideSwitcher`(第 291 行)
- 屏幕变化时 `didChangeScreenParametersNotification` 触发 `rebuildPanels()`。
- 设置变化时,`settings.objectWillChange` 的 sink 在下一轮调用 `refreshVisibleSwitcher()`(仅切换器打开时),最终走到 `updateSwitchers()`。

## 关键决定

1. **“主显示器”的定义**:`NSScreen.screens.first`,即系统设置 → 显示器里设为主显示器的屏幕(原点 (0,0))。不要用 `NSScreen.main`,它是当前 key window 所在的屏幕,含义不同。
2. **默认值 `allDisplays`**:老用户升级后行为不变。这是新增的 key,不需要迁移;缺失或非法值都回退到 `allDisplays`。
3. **面板仍按屏幕全部创建**,只在显示时过滤。这样切换设置不用重建面板,`rebuildPanels()` 的结构不变。
4. **单显示器时选项照常显示**,两个选项效果相同。不做按屏幕数量隐藏,否则拔掉外接屏后设置会消失。
5. **侧边栏不受影响**,`sidebars` 相关代码不动。

## 改动

### 1. Core:`Sources/OpenContextsCore/SwitcherDisplayMode.swift`(新文件)

目标屏幕的选择是纯逻辑,放在 Core 才能单测。用泛型,避免 Core 依赖 `CGDirectDisplayID`。

```swift
public enum SwitcherDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case allDisplays
    case primaryDisplay

    public var id: String { rawValue }

    /// `displays` must follow `NSScreen.screens` order, where the first entry is the primary display.
    public func targetDisplays<ID>(from displays: [ID]) -> [ID] {
        switch self {
        case .allDisplays: displays
        case .primaryDisplay: Array(displays.prefix(1))
        }
    }
}
```

### 2. Core 测试:`Tests/OpenContextsCoreTests/SwitcherDisplayModeTests.swift`(新文件)

先写测试,确认失败后再写实现。覆盖:

- `allDisplays` 返回全部屏幕,顺序不变
- `primaryDisplay` 只返回第一块屏幕
- 单屏时两种模式结果相同
- 空数组时两种模式都返回空数组(睡眠或合盖时 `NSScreen.screens` 可能为空)
- rawValue 固定为 `"allDisplays"`、`"primaryDisplay"`(已写入用户偏好,不能改名),未知字符串得到 `nil`

### 3. `Sources/OpenContexts/SettingsView.swift`

- 文件顶部和其他枚举放在一起,加 `extension SwitcherDisplayMode { func title(_ language: AppLanguage) -> String }`,分别返回 `"All displays"`、`"Primary display"` 的本地化文本。
- `AppSettings`:
  - 新增 `@Published private(set) var switcherDisplayMode: SwitcherDisplayMode`
  - `init` 中读取:`SwitcherDisplayMode(rawValue: defaults.string(forKey: "switcherDisplayMode") ?? "") ?? .allDisplays`
  - 新增 `setSwitcherDisplayMode(_:)`,写法和 `setSidebarMode` 一致,defaults key 为 `switcherDisplayMode`
- `AppSettings.selfCheck()` 增加:默认值是 `.allDisplays`;设为 `.primaryDisplay` 后新实例能读回;写入 `"invalid"` 后回退到 `.allDisplays`。注意不要破坏该函数后续断言依赖的 defaults 状态。
- `generalSettings`:在 `settingsRow("Window switcher")` 之后、`settingsRow("Language")` 之前加一行。样式沿用 Sidebar 页的横向单选:

```swift
settingsRow("Show switcher on") {
    VStack(alignment: .leading, spacing: 8) {
        Picker(L10n.text("Show switcher on", language: language), selection: Binding(
            get: { settings.switcherDisplayMode }, set: settings.setSwitcherDisplayMode
        )) {
            ForEach(SwitcherDisplayMode.allCases) { mode in
                Text(mode.title(language)).tag(mode)
            }
        }
        .pickerStyle(.radioGroup)
        .horizontalRadioGroupLayout()
        .labelsHidden()
        Text(L10n.text("The primary display is the one set as Main display in System Settings → Displays.", language: language))
            .foregroundStyle(.secondary)
    }
}
```

### 4. `Sources/OpenContexts/AppController.swift`

新增目标屏幕计算,并把显示逻辑收敛到两个方法。非目标面板在这里隐藏,这样切换器打开时改设置、或切换中屏幕变化,都能收敛到正确状态。

```swift
private var switcherDisplayIDs: Set<CGDirectDisplayID> {
    Set(settings.switcherDisplayMode.targetDisplays(from: NSScreen.screens.map(Self.displayID)))
}

private func showSwitchers() {
    let targets = switcherDisplayIDs
    for (id, panel) in switchers {
        guard targets.contains(id) else { panel.hideSwitcher(); continue }
        panel.show(results: switchingResults, selectedIndex: selectedIndex, query: searchQuery,
                   groupBySpace: settings.showWindowsFromAllDesktops,
                   totalWindowCount: switchingWindowCount, language: settings.language)
    }
}

private func updateSwitchers(resetHover: Bool = false) {
    let targets = switcherDisplayIDs
    for (id, panel) in switchers {
        guard targets.contains(id) else { panel.hideSwitcher(); continue }
        guard panel.isVisible else {
            panel.show(results: switchingResults, selectedIndex: selectedIndex, query: searchQuery,
                       groupBySpace: settings.showWindowsFromAllDesktops,
                       totalWindowCount: switchingWindowCount, language: settings.language)
            continue
        }
        panel.update(results: switchingResults, selectedIndex: selectedIndex, resetHover: resetHover,
                     groupBySpace: settings.showWindowsFromAllDesktops,
                     query: searchQuery, totalWindowCount: switchingWindowCount, language: settings.language)
    }
}
```

- `rebuildPanels()` 末尾和 `handle(.begin)` 里的 `switchers.values.forEach { $0.show(...) }` 都换成 `showSwitchers()`。`.begin` 时 `searchQuery` 已被清空,传 `query: searchQuery` 与原来的默认值等价。
- `finishSwitcher` **保持** `switchers.values.forEach { $0.hideSwitcher() }`,必须隐藏全部面板。
- `settings.objectWillChange` 的 sink 不用改,已有的 `refreshVisibleSwitcher()` 会走到 `updateSwitchers()`。
- 不改 `Panels.swift`。

### 5. 本地化(五份 `Localizable.strings`,key 集合必须一致)

追加在 `"Current desktop"` 之后:

| key | zh | ja | fr | es |
| --- | --- | --- | --- | --- |
| `Show switcher on` | 切换器显示位置 | 切替の表示先 | Afficher le sélecteur sur | Mostrar el selector en |
| `All displays` | 所有显示器 | すべてのディスプレイ | Tous les écrans | Todas las pantallas |
| `Primary display` | 主显示器 | 主ディスプレイ | Écran principal | Pantalla principal |
| `The primary display is the one set as Main display in System Settings → Displays.` | 主显示器是在系统设置 → 显示器中设为主显示器的屏幕。 | 主ディスプレイは、システム設定 → ディスプレイで主ディスプレイに設定した画面です。 | L’écran principal est celui défini comme moniteur principal dans Réglages Système → Moniteurs. | La pantalla principal es la definida como tal en Ajustes del Sistema → Pantallas. |

`en.lproj` 的值与 key 相同。

### 6. 文档

- `README.md` 功能表,`All desktops` 行之后加:
  `| Switcher display | Choose in Settings → General whether the window switcher appears on all displays or only on the primary display. All displays is the default |`
- `README.zh-CN.md` 同一位置加:
  `| 切换器显示位置 | 在设置 → 通用中选择窗口切换器显示在所有显示器还是仅主显示器，默认显示在所有显示器 |`
- `CONTEXT.md` 术语表加:
  `- **主显示器**：系统设置 → 显示器中设为主显示器的屏幕（`NSScreen.screens.first`），不是当前焦点所在的屏幕。`

## 不做的事

- 不加“跟随鼠标所在屏幕”或“跟随当前窗口所在屏幕”的模式。
- 不改 `website/`:官网演示只模拟单屏,这个选项在那里没有可演示的行为。
- 不改 `CHANGELOG.md`、`VERSION`(CHANGELOG 在发版时集中写)。
- 不动工作区里已有的未提交改动:`Sources/OpenContexts/WindowService.swift`、`.swiftformat`、`AGENTS.md`。
- 不提交、不推送。

## 验证

按顺序执行,全部要通过:

1. `swift test --filter SwitcherDisplayModeTests`:实现前确认失败,实现后确认通过
2. `swift test`
3. `swift build && .build/debug/OpenContexts --self-check`(覆盖设置持久化和五份语言文件的 key 一致性)
4. `.build/debug/OpenContexts --ui-self-check`(覆盖设置页布局)
5. `swiftformat Sources Tests --lint`

AppKit 部分测试 target 覆盖不到,需要在两块屏幕上实机确认:

1. 默认设置下按 `⌘Tab`,两块屏幕都出现切换器。
2. 改为 Primary display 后按 `⌘Tab`,只有主显示器出现,鼠标在副屏时也一样;键盘切换、搜索、鼠标点击都正常。
3. 重启应用后选项保留。
4. 在系统设置里更换主显示器后,切换器跟随到新的主显示器。
5. 拔掉主显示器后,切换器显示在剩下的屏幕上。
