# 窗口切换器“跟随鼠标”显示模式:实现文档

基于已提交的 `895b5af`(`SwitcherDisplayMode`:`allDisplays`、`primaryDisplay`、`focusedDisplay`,设置项已是下拉框)。

## 目标

新增第四种模式 `pointerDisplay`:切换器只显示在鼠标所在的屏幕。鼠标在主屏就显示在主屏,鼠标在第三块屏幕就显示在第三块屏幕。下拉框选项顺序:所有显示器、主显示器、焦点所在显示器、鼠标所在显示器。

## 行为定义

- **鼠标屏幕**:呼出切换器那一刻鼠标所在的屏幕,和焦点窗口在哪无关。
- **每次呼出锁定一次**,和 `focusedDisplay` 相同。切换器打开后移动鼠标不换屏,否则用户把鼠标移向列表时面板可能跳走。下次呼出重新计算。
- **例外**:切换过程中锁定的屏幕被拔掉,或用户把设置改成这个模式时,重新计算。
- **回退**:取不到鼠标所在屏幕时用主显示器。

## 关键决定

1. **鼠标位置用 `CGEvent(source: nil)?.location`,不用 `NSEvent.mouseLocation`。** `NSEvent.mouseLocation` 配 `NSRect.contains` 时,上边缘和右边缘不算在矩形内,鼠标贴在副屏顶部(菜单栏最上一行)时可能匹配不到屏幕,回退到主屏。`CGEvent` 的位置和 `CGDisplayBounds` 同为左上原点的全局坐标,可以用 1×1 矩形复用已有的 `SwitcherDisplayMode.display(containing:in:)`。
2. **`focusedDisplay` 的鼠标回退一起换成这个方法**,两个模式共用一处实现。
3. **把“焦点”相关命名改成通用的“锚点”**:`targetDisplays` 的 `focused:` 参数改为 `anchor:`,`switcherFocusDisplayID` 改为 `switcherAnchorDisplayID`。这两个模式现在共用这套逻辑,这些都是内部 API,不影响用户数据。
4. **默认值仍是 `allDisplays`**,已有 rawValue 不变,新增 `pointerDisplay`,不需要迁移。

## 改动

### 1. `Sources/OpenContextsCore/SwitcherDisplayMode.swift`

```swift
public enum SwitcherDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case allDisplays
    case primaryDisplay
    case focusedDisplay
    case pointerDisplay

    public var id: String { rawValue }

    /// Whether the mode shows the switcher on one display resolved when it opens.
    public var usesAnchorDisplay: Bool {
        switch self {
        case .allDisplays, .primaryDisplay: false
        case .focusedDisplay, .pointerDisplay: true
        }
    }

    /// `displays` must follow `NSScreen.screens` order, where the first entry is the primary display.
    public func targetDisplays<ID: Equatable>(from displays: [ID], anchor: ID? = nil) -> [ID] {
        switch self {
        case .allDisplays:
            displays
        case .primaryDisplay:
            Array(displays.prefix(1))
        case .focusedDisplay, .pointerDisplay:
            if let anchor, displays.contains(anchor) { [anchor] } else { Array(displays.prefix(1)) }
        }
    }

    // display(containing:in:) 保持不变
}
```

### 2. `Tests/OpenContextsCoreTests/SwitcherDisplayModeTests.swift`

先加测试,确认是断言失败后再写实现。为了让失败发生在断言而不是编译阶段,先完成 `focused:` → `anchor:` 改名,并加上 `pointerDisplay` case 和 `usesAnchorDisplay`,新分支先写成错误的占位实现。

已有测试里的 `focused:` 全部改成 `anchor:`。新增用例:

- `pointerDisplay` 且锚点存在:只返回该屏幕(用三块屏幕,锚点取第三块)
- `pointerDisplay` 且 `anchor` 为 `nil`:返回第一块屏幕
- `pointerDisplay` 且 `anchor` 不在列表里:返回第一块屏幕
- `pointerDisplay` 且屏幕列表为空:返回空数组
- `pointerDisplay` 的 rawValue 固定
- `usesAnchorDisplay`:`focusedDisplay`、`pointerDisplay` 为 true,其余为 false
- `display(containing:in:)` 用 1×1 矩形:鼠标在第三块屏幕内;鼠标在屏幕左上角;鼠标在屏幕最右下像素;鼠标在负坐标屏幕上

### 3. `Sources/OpenContexts/AppController.swift`

把 `switcherFocusDisplayID` 全部改名为 `switcherAnchorDisplayID`,然后:

```swift
private func switcherTargetDisplayIDs() -> Set<CGDirectDisplayID> {
    let displays = NSScreen.screens.map(Self.displayID)
    let mode = settings.switcherDisplayMode
    if mode.usesAnchorDisplay {
        if switcherAnchorDisplayID.map(displays.contains) != true {
            switcherAnchorDisplayID = currentAnchorDisplayID(for: mode) ?? displays.first
        }
    } else {
        switcherAnchorDisplayID = nil
    }
    return Set(mode.targetDisplays(from: displays, anchor: switcherAnchorDisplayID))
}

private func currentAnchorDisplayID(for mode: SwitcherDisplayMode) -> CGDirectDisplayID? {
    let displays = NSScreen.screens.map(Self.displayID).map { (id: $0, bounds: CGDisplayBounds($0)) }
    if mode == .focusedDisplay, let frame = windowService.frontmostWindowFrame(),
       let id = SwitcherDisplayMode.display(containing: frame, in: displays) {
        return id
    }
    guard let pointer = CGEvent(source: nil)?.location else { return nil }
    return SwitcherDisplayMode.display(containing: CGRect(origin: pointer, size: CGSize(width: 1, height: 1)),
                                       in: displays)
}
```

`handle(.begin)`、`finishSwitcher` 里清空锚点的位置不变,只是改名。删除原来的 `currentFocusDisplayID()`。

### 4. `Sources/OpenContexts/SettingsView.swift`

`extension SwitcherDisplayMode`:

- `title(_:)` 增加 `.pointerDisplay` → `"Pointer display"`
- `caption(_:)` 增加 `.pointerDisplay` → `"Shows on the display under the pointer."`

下拉框用 `ForEach(allCases)`,不用改。`AppSettings.selfCheck()` 已经遍历 `allCases`,也不用改。

### 5. 本地化(五份 `Localizable.strings`,追加在上次新增的 key 之后)

| key | zh | ja | fr | es |
| --- | --- | --- | --- | --- |
| `Pointer display` | 鼠标所在显示器 | ポインタのあるディスプレイ | Écran du pointeur | Pantalla del puntero |
| `Shows on the display under the pointer.` | 显示在鼠标所在的屏幕。 | ポインタのある画面に表示します。 | S’affiche sur l’écran où se trouve le pointeur. | Se muestra en la pantalla donde está el puntero. |

`en.lproj` 的值与 key 相同。

### 6. 文档

- `README.md` 的 `Switcher display` 行改为:
  `| Switcher display | Choose in Settings → General whether the window switcher appears on all displays, only on the primary display, on the display with the focused window, or on the display under the pointer. All displays is the default |`
- `README.zh-CN.md` 的 `切换器显示位置` 行改为:
  `| 切换器显示位置 | 在设置 → 通用中选择窗口切换器显示在所有显示器、仅主显示器、焦点窗口所在的显示器，或鼠标所在的显示器，默认显示在所有显示器 |`
- `CONTEXT.md` 在 `焦点显示器` 之后加:
  `- **鼠标显示器**：呼出窗口切换器时鼠标所在的屏幕。`

## 不做的事

- 不改 `handle(.toggleSidebar)` 里侧边栏的取屏逻辑,它用的还是 `NSEvent.mouseLocation`。
- 不改 `Panels.swift`、`WindowService.swift`、`website/`、`CHANGELOG.md`、`VERSION`。
- 不动工作区里已有的未提交改动:`WindowService.swift` 的那一行、`.swiftformat`、`AGENTS.md`、`docs/plans/`。
- 不提交、不推送。

## 验证

按顺序执行,全部要通过,用直接的退出码判断:

1. `swift test --filter SwitcherDisplayModeTests`:实现前确认是断言失败,实现后确认通过
2. `swift test`
3. `swift build && .build/debug/OpenContexts --self-check`
4. `.build/debug/OpenContexts --ui-self-check`:这一项曾偶发失败,报 `sidebar context menu lifecycle mismatch`。如果失败,要如实汇报报错原文和重跑结果,不要只报最后一次
5. `swiftformat Sources Tests --lint`

需要多块屏幕实机确认:

1. 选 Pointer display,鼠标分别放在每块屏幕上按 `⌘Tab`,切换器只出现在鼠标所在的屏幕,和焦点窗口在哪无关。
2. 鼠标贴在副屏最顶部和最右侧时,切换器仍显示在这块副屏。
3. 切换器打开后把鼠标移到其他屏幕,切换器不换屏;松开后再呼出,切换器跟过去。
4. Focused display 在前台没有窗口时,仍回退到鼠标所在屏幕。
5. 下拉框有四个选项,说明文字随选项变化,重启后选项保留。
6. All displays、Primary display、Focused display 的行为和之前一样。
