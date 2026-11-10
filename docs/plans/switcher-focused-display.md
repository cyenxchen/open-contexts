# 窗口切换器“跟随焦点”显示模式:实现文档

基于已提交的 `c41a4f6`(`SwitcherDisplayMode`:`allDisplays`、`primaryDisplay`)。

## 目标

1. 新增第三种模式 `focusedDisplay`:切换器只显示在当前焦点窗口所在的屏幕。例如焦点窗口在第二块屏幕,切换器就显示在第二块屏幕。
2. General 页的这个设置从横向单选改成下拉框,样式和 Language 一致。

## 行为定义

- **焦点屏幕**:前台应用最靠前的普通窗口所在的屏幕。窗口跨屏时取重叠面积最大的屏幕。
- **回退顺序**:焦点窗口所在屏幕 → 鼠标所在屏幕 → 主显示器。前台应用没有可见窗口时(比如焦点在桌面上)走到鼠标所在屏幕。
- **每次呼出锁定一次**:在切换器打开时确定屏幕,之后按 Tab 选择、搜索、窗口列表刷新都不换屏。下次呼出重新计算。
- **例外**:切换过程中锁定的屏幕被拔掉,或用户把设置改成这个模式时,重新计算。

## 关键决定

1. **用 `CGWindowListCopyWindowInfo`,不用 AX 查询。** `.begin` 在主线程上,对目标应用做 AX 查询时,卡死的应用会让 `⌘Tab` 明显变慢(超时 0.2 秒,要查多次)。窗口服务器查询不经过目标应用,而且 `focusedWindowID` 是扫描发布的,可能滞后。
2. **坐标**:`kCGWindowBounds` 和 `CGDisplayBounds` 同为左上原点的全局坐标,直接比较,不要用 `NSScreen.frame` 比较(它是左下原点)。`NSEvent.mouseLocation` 和 `NSScreen.frame` 同为左下原点,鼠标回退用这一对。
3. **只在 `focusedDisplay` 模式下查询**,其他模式的 `⌘Tab` 路径不增加开销。
4. **默认值仍是 `allDisplays`**,已有 rawValue 不变,新增 `focusedDisplay`,不需要迁移。

## 改动

### 1. `Sources/OpenContextsCore/SwitcherDisplayMode.swift`

```swift
import CoreGraphics

public enum SwitcherDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case allDisplays
    case primaryDisplay
    case focusedDisplay

    public var id: String { rawValue }

    /// `displays` must follow `NSScreen.screens` order, where the first entry is the primary display.
    public func targetDisplays<ID: Equatable>(from displays: [ID], focused: ID? = nil) -> [ID] {
        switch self {
        case .allDisplays:
            displays
        case .primaryDisplay:
            Array(displays.prefix(1))
        case .focusedDisplay:
            if let focused, displays.contains(focused) { [focused] } else { Array(displays.prefix(1)) }
        }
    }

    /// Returns the display overlapping `frame` the most, or nil when nothing overlaps.
    public static func display<ID>(containing frame: CGRect, in displays: [(id: ID, bounds: CGRect)]) -> ID? {
        // 面积相同时取靠前的屏幕
    }
}
```

`display(containing:in:)` 按 `bounds.intersection(frame)` 的面积取最大值;空交集按 0 计;全部为 0 时返回 `nil`。

### 2. `Tests/OpenContextsCoreTests/SwitcherDisplayModeTests.swift`

先加测试,确认断言失败后再写实现。为了让失败发生在断言而不是编译阶段,先加上 `focusedDisplay` case 和方法签名,`targetDisplays` 的新分支和 `display(containing:in:)` 先写成错误的占位实现。

新增用例:

- `focusedDisplay` 且焦点屏幕存在:只返回该屏幕
- `focusedDisplay` 且 `focused` 为 `nil`:返回第一块屏幕
- `focusedDisplay` 且 `focused` 不在列表里(屏幕已拔掉):返回第一块屏幕
- `focusedDisplay` 且屏幕列表为空:返回空数组
- `allDisplays`、`primaryDisplay` 忽略 `focused` 参数
- `focusedDisplay` 的 rawValue 固定
- `display(containing:in:)`:窗口完全在第二块屏幕;跨屏取重叠大的;面积相同取靠前的;不与任何屏幕重叠返回 `nil`;负坐标屏幕(副屏在主屏左侧或上方)能命中

已有的 `testBothModesSelectTheOnlyDisplay` 和 `testBothModesHandleNoDisplays` 遍历 `allCases`,要继续通过。

### 3. `Sources/OpenContexts/WindowService.swift`

文件里有用户尚未提交的一行改动(`var windowID: CGWindowID?`),保留它,不要还原,也不要把它算进这次改动的说明。

在 `onScreenWindowFrames()` 附近加:

```swift
/// Reads from the window server only, so a hung app cannot delay the switcher.
func frontmostWindowFrame() -> CGRect? {
    guard let processID = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
    return Self.onScreenWindowFrames()[processID]?.first { $0.width >= 50 && $0.height >= 50 }
}
```

`onScreenWindowFrames()` 已只取 layer 0,并排除桌面元素,返回顺序为从前到后。侧边栏(`.floating`)和切换器(`.popUpMenu`)不在 layer 0,不会干扰。尺寸过滤用来跳过部分应用的隐藏小窗口。

### 4. `Sources/OpenContexts/AppController.swift`

- 新增 `private var switcherFocusDisplayID: CGDirectDisplayID?`
- 把 `switcherDisplayIDs` 计算属性换成方法,因为它现在要写入锁定值:

```swift
private func switcherTargetDisplayIDs() -> Set<CGDirectDisplayID> {
    let displays = NSScreen.screens.map(Self.displayID)
    if settings.switcherDisplayMode == .focusedDisplay,
       switcherFocusDisplayID.map(displays.contains) != true {
        switcherFocusDisplayID = currentFocusDisplayID()
    }
    return Set(settings.switcherDisplayMode.targetDisplays(from: displays, focused: switcherFocusDisplayID))
}

private func currentFocusDisplayID() -> CGDirectDisplayID? {
    let displays = NSScreen.screens.map(Self.displayID).map { (id: $0, bounds: CGDisplayBounds($0)) }
    if let frame = windowService.frontmostWindowFrame(),
       let id = SwitcherDisplayMode.display(containing: frame, in: displays) {
        return id
    }
    return NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }).map(Self.displayID)
}
```

- `showSwitchers()`、`updateSwitchers(resetHover:)` 改用 `switcherTargetDisplayIDs()`。
- `handle(.begin)`:在 `showSwitchers()` 之前把 `switcherFocusDisplayID` 置为 `nil`,保证每次呼出重新计算。
- `finishSwitcher`:同样置为 `nil`,仍然隐藏全部面板。
- `rebuildPanels()` 不用改,`showSwitchers()` 会处理屏幕被拔掉的情况。

### 5. `Sources/OpenContexts/SettingsView.swift`

- `extension SwitcherDisplayMode`:
  - `title(_:)` 增加 `.focusedDisplay` → `"Focused display"`
  - 新增 `func caption(_ language: AppLanguage) -> String?`:`allDisplays` 返回 `nil`,`primaryDisplay` 返回已有说明文字,`focusedDisplay` 返回新说明文字
- `generalSettings` 的 `settingsRow("Show switcher on")`:去掉 `.pickerStyle(.radioGroup)` 和 `.horizontalRadioGroupLayout()`,改成和 Language 一样的默认下拉样式,`.labelsHidden()` 加 `.frame(width: 200)`。说明文字改为按当前选项显示,`caption` 为 `nil` 时不渲染:

```swift
if let caption = settings.switcherDisplayMode.caption(language) {
    Text(caption).foregroundStyle(.secondary)
}
```

- `AppSettings.selfCheck()`:把持久化检查扩展到 `.focusedDisplay`,用 `SwitcherDisplayMode.allCases` 遍历读回,最后恢复 `.allDisplays`。

### 6. 本地化(五份 `Localizable.strings`,追加在上次新增的 key 之后)

| key | zh | ja | fr | es |
| --- | --- | --- | --- | --- |
| `Focused display` | 焦点所在显示器 | フォーカスのあるディスプレイ | Écran de la fenêtre active | Pantalla de la ventana activa |
| `Shows on the display with the focused window, or under the pointer if there is none.` | 显示在焦点窗口所在的屏幕;没有焦点窗口时显示在鼠标所在的屏幕。 | フォーカスのあるウインドウの画面に表示します。ウインドウがない場合はポインタのある画面に表示します。 | S’affiche sur l’écran de la fenêtre active, ou sur celui du pointeur s’il n’y en a pas. | Se muestra en la pantalla de la ventana activa o, si no hay ninguna, en la del puntero. |

`en.lproj` 的值与 key 相同。

### 7. 文档

- `README.md` 的 `Switcher display` 行改为:
  `| Switcher display | Choose in Settings → General whether the window switcher appears on all displays, only on the primary display, or on the display with the focused window. All displays is the default |`
- `README.zh-CN.md` 的 `切换器显示位置` 行改为:
  `| 切换器显示位置 | 在设置 → 通用中选择窗口切换器显示在所有显示器、仅主显示器，或焦点窗口所在的显示器，默认显示在所有显示器 |`
- `CONTEXT.md` 在 `主显示器` 之后加:
  `- **焦点显示器**：前台应用最靠前的窗口所在的屏幕；没有这样的窗口时取鼠标所在的屏幕。`

## 不做的事

- 不改 `Panels.swift`、`website/`、`CHANGELOG.md`、`VERSION`。
- 不重构 `fullscreenDisplays`,它的取屏逻辑保持原样。
- 不动工作区里已有的未提交改动:`WindowService.swift` 的那一行、`.swiftformat`、`AGENTS.md`、`docs/plans/`。
- 不提交、不推送。

## 验证

按顺序执行,全部要通过,用直接的退出码判断:

1. `swift test --filter SwitcherDisplayModeTests`:实现前确认是断言失败,实现后确认通过
2. `swift test`
3. `swift build && .build/debug/OpenContexts --self-check`
4. `.build/debug/OpenContexts --ui-self-check`
5. `swiftformat Sources Tests --lint`

需要两块屏幕实机确认:

1. 选 Focused display,焦点窗口在副屏时按 `⌘Tab`,切换器只出现在副屏;焦点窗口在主屏时只出现在主屏,和鼠标位置无关。
2. 焦点窗口跨两块屏幕时,显示在占比大的一块。
3. 全屏应用在副屏时,切换器显示在副屏的全屏空间上。
4. 点击桌面让前台应用没有窗口时,切换器显示在鼠标所在屏幕。
5. 切换过程中按 Tab、输入搜索,切换器不换屏;切到另一块屏幕的窗口后再按 `⌘Tab`,切换器跟过去。
6. 设置页里下拉框显示三个选项,样式和 Language 一致,切换选项时说明文字随之变化,重启后选项保留。
7. All displays、Primary display 的行为和之前一样。
