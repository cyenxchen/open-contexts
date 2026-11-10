# 快捷键唤出搜索:实现文档

基于已提交的 `c20cb51`。

## 目标

用一个快捷键唤出窗口切换器,唤出后直接输入关键字过滤,按回车切换到选中的窗口。不需要按住修饰键。

- General 页有开关,控制是否启用这个功能。
- 默认快捷键 `⌥Space`,可以在 Shortcuts 页修改。

## 行为定义

| 操作 | 结果 |
| --- | --- |
| 按快捷键 | 打开切换器,列出全部窗口,搜索框显示闪烁光标 |
| 松开修饰键 | 不关闭,切换器保持打开 |
| 输入字符 | 过滤列表,选中第一条 |
| `Backspace` | 删除字符 |
| `↑`、`↓`、`Tab`、`⇧Tab` | 移动选中项 |
| `Return`、小键盘 `Enter` | 切换到选中窗口,没有匹配结果时只关闭 |
| 鼠标点击列表行 | 切换到该窗口 |
| `Esc` | 取消 |
| 再按一次快捷键 | 取消,长按时的自动重复不算 |
| 点击切换器以外的地方 | 取消 |
| 前台应用变化 | 取消 |

其余行为和 `⌘Tab` 一致:窗口范围遵守“显示所有桌面的窗口”,显示位置遵守 `switcherDisplayMode`,初始选中项也相同(第一条是当前窗口时选中第二条,所以按快捷键再按回车会回到上一个窗口)。

## 关键决定

1. **继续用事件 tap 接收输入,不做真正可编辑的文本框。** `SwitcherPanel` 不能成为 key window,现有搜索就是由 tap 吞掉按键再写入 query。tap 在输入法之前拿到按键,所以中文输入法开着时敲拼音也能直接匹配。代价和现有搜索相同:只支持可打印 ASCII,不能直接输入中文,不支持粘贴。
2. **必须有自动关闭。** 普通切换靠松开修饰键结束,这个模式没有这个出口。如果用户点去别的窗口而切换器还开着,所有按键都会被吞掉。所以要加“点击外部”和“前台应用变化”两种关闭方式,这是硬性要求。
3. **开关默认关闭。** `⌥Space` 在 macOS 上会输入不换行空格,也常被其他工具占用。默认开启会让升级用户的按键行为突然改变。
4. **开关和快捷键分开存**:`searchShortcutEnabled`(Bool,默认 false)和 `searchShortcut`。关掉再打开,自定义的快捷键还在。
5. **功能关闭时,它的快捷键不参与冲突检查。** 否则已把 `⌥Space` 用在别处的老用户、或想把它录给其他功能的用户,会被一个没开启的功能挡住。开启时如果有冲突,快捷键不生效,并在 General 页显示红字提示。

## 改动

### 1. `Sources/OpenContexts/ShortcutController.swift`

- `KeyboardShortcut` 加 `static let search = KeyboardShortcut(keyCode: 49, modifiers: .maskAlternate, keyLabel: "Space")`
- `ShortcutTarget` 加 `case search`(放在最后,设置页按 `allCases` 顺序显示),`title` 返回 `"Search windows"`。defaults key 由 `target.rawValue + "Shortcut"` 得到 `searchShortcut`。
- `SwitcherAction` 加 `case beginSearch`
- `ShortcutState`:
  - 加 `private(set) var isSearchSession = false`
  - 加 `mutating func beginSearch(allowed: Bool) -> SwitcherAction?`:规则和 `begin` 相同,`isSwitching = true`、`isSearchSession = true`、`heldModifiers = []`,返回 `.beginSearch`
  - `begin` 和 `finish` 把 `isSearchSession` 置回 `false`
- `ShortcutController`:
  - 加 `private(set) var searchShortcut: KeyboardShortcut?`,默认 `nil`
  - `configure` 加参数 `search: KeyboardShortcut? = nil`,校验规则和 `sidebar` 相同(有效,且不与其他三个冲突),并加入“是否变化”的判断
  - `modifierAction` 在 `state.isSearchSession` 时返回 `nil`,不要依赖 `flags.contains([])` 的隐含行为
  - `keyAction` 加参数 `isRepeat: Bool = false`,`handle` 传入 `event.getIntegerValueField(.keyboardEventAutorepeat) != 0`
  - `keyAction` 在 `if state.isSwitching` 块的开头加:

```swift
if state.isSearchSession {
    if !flags.contains(.maskShift), searchShortcut?.matches(keyCode: keyCode, flags: flags) == true {
        return isRepeat ? nil : state.finish(commit: false)
    }
    if keyCode == 36 || keyCode == 76 { return state.finish(commit: true) }
}
```

  - 同一块的 `default` 分支:`state.isSearchSession` 且 `flags` 含 `.maskCommand` 或 `.maskControl` 时不追加字符(返回 `nil`,按键仍被吞掉)。普通切换必须按住修饰键,所以保持原逻辑。
  - `isSwitching` 块之后、`allWindowsShortcut` 判断之前加:

```swift
if !flags.contains(.maskShift), searchShortcut?.matches(keyCode: keyCode, flags: flags) == true {
    return state.beginSearch(allowed: canBegin?(false) ?? true)
}
```

  - `handle` 里 `Self.searchCharacters` 不用改,`⌥` 按住时也会得到不带修饰的字符。
  - 注意:新分支要放在 `sidebarShortcut` 判断之后,保持侧边栏快捷键优先。

### 2. `selfCheck()` 增加断言

先写断言再实现。为了能编译,先加好类型和方法签名,行为留成错误的占位实现,确认 `--self-check` 退出 1 后再实现。

- `KeyboardShortcut.search.display == "⌥Space"`、`isValid`
- `search` 为 `nil` 时 `⌥Space` 返回 `nil`
- 配置后:`⌥Space` 得到 `.beginSearch`;`⇧⌥Space` 得到 `nil`;`canBegin` 为 false 时得到 `nil`
- 打开后:`modifierAction(flags: [])` 返回 `nil`;字符得到 `.search`;`⌥` 按住时输入字符也得到 `.search`;带 `⌘` 或 `⌃` 的字符不进 query;`↑`、`↓`、`Tab` 得到 `.step`;`Backspace` 得到 `.search`
- `Return`(36)和 `Enter`(76)得到 `.commit`;`Esc` 得到 `.cancel`
- 再按 `⌥Space` 且 `isRepeat: false` 得到 `.cancel`;`isRepeat: true` 时得到 `nil`,且切换器保持打开
- 普通 `⌘Tab` 切换时 `Return` 仍然不提交,松开修饰键仍然提交
- `configure` 拒绝与其他快捷键冲突的 `search`

### 3. `Sources/OpenContexts/SettingsView.swift`

`AppSettings`:

```swift
@Published private(set) var searchShortcut: KeyboardShortcut
@Published private(set) var searchShortcutEnabled: Bool

var searchShortcutHasConflict: Bool {
    [allWindowsShortcut, currentAppShortcut, sidebarShortcut].compactMap { $0 }
        .contains { searchShortcut.conflicts(with: $0) }
}

var activeSearchShortcut: KeyboardShortcut? {
    searchShortcutEnabled && !searchShortcutHasConflict ? searchShortcut : nil
}
```

- `init`:`searchShortcut = loadShortcut("searchShortcut", fallback: .search)`,`searchShortcutEnabled = defaults.object(forKey: "searchShortcutEnabled") as? Bool ?? false`
- 新增 `setSearchShortcutEnabled(_:)`
- `setShortcut`:`others` 排除 `target` 本身,并在 `!searchShortcutEnabled` 时排除 `.search`。`switch` 加 `case .search: searchShortcut = shortcut`
- `shortcut(for:)` 加 `case .search: searchShortcut`
- `resetShortcuts`:`searchShortcut = .search`,移除 `searchShortcut` key,**不改**开关状态
- `selfCheck` 增加:默认关闭、`activeSearchShortcut` 为 `nil`;开启后读回;自定义快捷键持久化;关掉再打开快捷键还在;`resetShortcuts` 恢复快捷键但不动开关;功能关闭时其他目标可以录 `⌥Space`;此时开启后 `searchShortcutHasConflict` 为 true、`activeSearchShortcut` 为 `nil`;功能开启时其他目标不能录它

`generalSettings`:在 `settingsRow("Show switcher on")` 之后加一行:

```swift
settingsRow("Window search") {
    VStack(alignment: .leading, spacing: 8) {
        Toggle(L10n.text("Open the switcher with a shortcut to search", language: language), isOn: Binding(
            get: { settings.searchShortcutEnabled }, set: settings.setSearchShortcutEnabled
        ))
        Text(L10n.format("Press %@, type to filter, then press Return to switch. Esc cancels.",
                         settings.searchShortcut.display, language: language))
            .foregroundStyle(.secondary)
        if settings.searchShortcutEnabled, settings.searchShortcutHasConflict {
            Text(L10n.text("This shortcut is already in use. Change it in Shortcuts.", language: language))
                .foregroundStyle(.red)
        }
    }
    .toggleStyle(.checkbox)
}
```

`shortcutSettings` 用 `ForEach(ShortcutTarget.allCases)`,新行自动出现,不用改。功能关闭时这一行仍可修改。

### 4. `Sources/OpenContexts/AppController.swift`

- 两处 `shortcuts.configure(...)` 都传 `search: settings.activeSearchShortcut`
- 新增 `private var isSearchSession = false`
- 把 `.begin` 分支的主体提取成 `private func beginSwitcher(currentAppOnly: Bool, reverse: Bool, searchSession: Bool)`,`.begin` 传 `false`,`.beginSearch` 传 `(false, false, true)`。`switchingResults` 为空时直接返回,不进入搜索状态
- `showSwitchers`、`updateSwitchers` 把 `searchFocused: isSearchSession` 传给面板
- 搜索状态下的自动关闭,打开时安装,`finishSwitcher` 开头移除:

```swift
private var searchDismissMonitors: [Any] = []
private var searchDismissObserver: NSObjectProtocol?

private func startSearchDismissal() {
    let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    // The global monitor sees clicks in other apps; the local one sees our sidebar and settings.
    if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
        DispatchQueue.main.async { self?.finishSwitcher(activating: nil) }
    }) { searchDismissMonitors.append(monitor) }
    if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
        if !(event.window is SwitcherPanel) {
            DispatchQueue.main.async { self?.finishSwitcher(activating: nil) }
        }
        return event
    }) { searchDismissMonitors.append(monitor) }
    searchDismissObserver = NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
    ) { [weak self] _ in
        Task { @MainActor in self?.finishSwitcher(activating: nil) }
    }
}

private func stopSearchDismissal() {
    searchDismissMonitors.forEach(NSEvent.removeMonitor)
    searchDismissMonitors = []
    if let searchDismissObserver {
        NSWorkspace.shared.notificationCenter.removeObserver(searchDismissObserver)
    }
    searchDismissObserver = nil
}
```

- `finishSwitcher`:开头调用 `stopSearchDismissal()`,并把 `isSearchSession` 置回 `false`。`windowService.activate(id)` 在它之后,所以提交时不会被“前台应用变化”再触发一次。
- 异步投递的取消可能晚于一次新的呼出:`finishSwitcher(activating: nil)` 的闭包只在 `isSearchSession` 仍为 true 时执行,普通 `⌘Tab` 不受影响。

### 5. `Sources/OpenContexts/Panels.swift`

`SwitcherPanel.show`、`update` 加参数 `searchFocused: Bool = false`。在搜索框里显示闪烁光标:

- 加一个 2pt 宽、16pt 高的 `NSView`,用 `layer.backgroundColor` 取强调色,闪烁用 `CABasicAnimation`(opacity,`repeatCount = .infinity`,`autoreverses`),约 0.5 秒
- 两条约束二选一:query 为空时贴在 `queryLabel.leadingAnchor`(占位文字之前),有内容时贴在 `queryLabel.trailingAnchor`
- `searchFocused == false` 时隐藏并移除动画,普通切换的外观不变
- 不改 `canBecomeKey`、`canBecomeMain`
- 加 `smokeSearchCaret`,`PanelSmokeCheck` 里验证:默认隐藏;`searchFocused: true` 时可见,query 为空和非空时位置符合上面的规则;再次 `update` 不传时隐藏

### 6. 本地化(五份 `Localizable.strings`,追加在末尾)

`Window search` 已存在,不用加。

| key | zh | ja | fr | es |
| --- | --- | --- | --- | --- |
| `Search windows` | 搜索窗口 | ウインドウを検索 | Rechercher des fenêtres | Buscar en las ventanas |
| `Open the switcher with a shortcut to search` | 使用快捷键唤出切换器进行搜索 | ショートカットで切替を開いて検索 | Ouvrir le sélecteur avec un raccourci pour rechercher | Abrir el selector con un atajo para buscar |
| `Press %@, type to filter, then press Return to switch. Esc cancels.` | 按 %@ 后输入关键字过滤，按回车切换，按 Esc 取消。 | %@ を押して入力で絞り込み、Return で切り替えます。Esc でキャンセルします。 | Appuyez sur %@, saisissez pour filtrer, puis appuyez sur Retour pour basculer. Échap annule. | Pulsa %@, escribe para filtrar y pulsa Retorno para cambiar. Esc cancela. |
| `This shortcut is already in use. Change it in Shortcuts.` | 这个快捷键已被占用，请在“快捷键”页修改。 | このショートカットは使用中です。「ショートカット」で変更してください。 | Ce raccourci est déjà utilisé. Modifiez-le dans Raccourcis. | Este atajo ya está en uso. Cámbialo en Atajos. |

`en.lproj` 的值与 key 相同。

顺带修正 `zh.lproj` 里的一处标点:`"Shows on the display with the focused window, or under the pointer if there is none."` 的值把半角 `;` 改成全角 `；`。

### 7. 文档

- `README.md` 功能表 `Window search` 行之后加:
  `| Search shortcut | Enable it in Settings → General, then press `⌥Space` to open the switcher ready for typing, filter by name, and press Return to switch. No key needs to be held. Change the shortcut in Settings → Shortcuts |`
- `README.zh-CN.md` 功能表 `窗口搜索` 行之后加:
  `| 搜索快捷键 | 在设置 → 通用中开启后，按 `⌥Space` 唤出切换器并直接输入过滤，按回车切换，无需按住修饰键。可在设置 → 快捷键中修改 |`
- `CONTEXT.md` 在 `窗口切换器` 之后加:
  `- **搜索唤出**：用单独的快捷键打开窗口切换器，不需要按住修饰键，输入过滤后按回车切换；点击别处或前台应用变化时自动关闭。`

## 不做的事

- 不做可编辑的文本框,不支持输入法直接输入中文和粘贴。
- 搜索状态下不改变现有的匹配规则。
- 不改 `website/`、`CHANGELOG.md`、`VERSION`。
- 不动工作区里已有的未提交改动:`WindowService.swift` 的那一行、`.swiftformat`、`AGENTS.md`、`docs/plans/`。
- 不提交、不推送。

## 验证

按顺序执行,全部要通过,用直接的退出码判断:

1. `swift build && .build/debug/OpenContexts --self-check`:实现前确认因新增断言失败(退出 1),实现后退出 0
2. `swift test`
3. `.build/debug/OpenContexts --ui-self-check`:曾偶发失败,报 `sidebar context menu lifecycle mismatch`。任何失败都要如实汇报报错原文和重跑结果
4. `swiftformat Sources Tests --lint`

需要实机确认:

1. 默认关闭时,`⌥Space` 在其他应用里行为不变。
2. 开启后按 `⌥Space`,切换器打开,搜索框有闪烁光标,松开 `⌥` 后不关闭。
3. 输入关键字过滤,`↑`、`↓`、`Tab` 移动选中项,回车切换到选中窗口。
4. 中文输入法开着时输入 `weixin` 能匹配。
5. `Esc`、再按一次 `⌥Space`、点击其他应用的窗口、点击桌面、点击侧边栏,切换器都关闭,且之后键盘输入恢复正常。
6. 长按 `⌥Space` 不会闪烁开关,也不会往搜索框里输入空格。
7. 在 Shortcuts 页改掉快捷键后新快捷键生效,旧的恢复原有行为;关掉开关再打开,自定义快捷键还在。
8. 如果 `⌥Space` 已被其他工具占用,确认谁优先生效,并记录下来。
9. `⌘Tab`、当前应用窗口切换的行为不变。
