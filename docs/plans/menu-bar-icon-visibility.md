# 隐藏菜单栏图标:实现文档

基于已提交的 `6d42d6d`。

## 目标

在设置 → General 新增一个选项,可以隐藏 OpenContexts 的菜单栏图标。默认不隐藏。

## 行为定义

- **勾选后**:菜单栏图标立即消失,不用重启。切换器、侧边栏、全局快捷键都不受影响。设置窗口保持打开。
- **取消勾选后**:图标立即恢复。
- **重启后**:选项保留。隐藏状态下启动时图标不出现。
- **回到设置的入口**:应用已经在运行时,再次打开它(Finder、“应用程序”文件夹、Spotlight、`open`)会显示设置窗口。这个行为不区分图标是否隐藏,图标显示时再次打开也会显示设置窗口。
- **缺少辅助功能授权时**:启动时自动打开设置的逻辑不变,隐藏图标不影响它。

## 关键决定

1. **必须保留回到设置的入口。** 菜单栏菜单是“设置”“检查更新”“授予辅助功能权限”“退出”的唯一入口,应用又是 `LSUIElement`,没有 Dock 图标。不处理的话,用户隐藏图标后只能改偏好文件才能恢复。用 `applicationShouldHandleReopen(_:hasVisibleWindows:)` 解决。
2. **“检查更新”和“退出”不在设置页另加按钮。** 用户重新打开设置、取消隐藏后就能用这些菜单项,不为这个选项增加新的 UI。
3. **用 `NSStatusItem.isVisible` 控制,不销毁 status item。** 菜单和 `statusItem` 引用保持不变,`configureMenuBar()` 不用分两条路径。
4. **在 `configureMenuBar()` 末尾设置可见性。** 它在启动时和每次设置变化时都会运行(见 `settings.objectWillChange` 的 sink),不需要新增监听。
5. **默认值 `false`。** 这是新增的 key,缺失时图标显示,老用户升级后行为不变,不需要迁移。

## 改动

### 1. `Sources/OpenContexts/SettingsView.swift`

`AppSettings`,写法和 `searchShortcutEnabled` 一致:

```swift
@Published private(set) var hideMenuBarIcon: Bool

func setHideMenuBarIcon(_ hidden: Bool) {
    hideMenuBarIcon = hidden
    defaults.set(hidden, forKey: "hideMenuBarIcon")
}
```

`init` 中读取:

```swift
hideMenuBarIcon = defaults.bool(forKey: "hideMenuBarIcon")
```

`AppSettings.selfCheck()` 在最后的 `return true` 之前增加:

```swift
guard check(!settings.hideMenuBarIcon, "menu bar icon must stay visible by default") else { return false }
settings.setHideMenuBarIcon(true)
guard check(AppSettings(defaults: defaults).hideMenuBarIcon, "hidden menu bar icon must persist") else { return false }
settings.setHideMenuBarIcon(false)
guard check(!AppSettings(defaults: defaults).hideMenuBarIcon,
            "restored menu bar icon must persist") else { return false }
```

`generalSettings`:在 `settingsRow("Window search")` 之后、`settingsRow("Language")` 之前加一行:

```swift
settingsRow("Menu bar") {
    VStack(alignment: .leading, spacing: 8) {
        Toggle(L10n.text("Hide menu bar icon", language: language), isOn: Binding(
            get: { settings.hideMenuBarIcon }, set: settings.setHideMenuBarIcon
        ))
        Text(L10n.text("While the icon is hidden, open OpenContexts again from Applications or Spotlight to show Settings.",
                       language: language))
            .foregroundStyle(.secondary)
    }
    .toggleStyle(.checkbox)
}
```

### 2. `Sources/OpenContexts/AppController.swift`

`configureMenuBar()` 的 `statusItem = item` 之前加:

```swift
item.isVisible = !settings.hideMenuBarIcon
```

新增代理方法,放在 `applicationWillTerminate(_:)` 之后:

```swift
func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    showSettings()
    return false
}
```

### 3. 本地化(五份 `Localizable.strings`,追加在文件末尾)

| key | zh | ja | fr | es |
| --- | --- | --- | --- | --- |
| `Menu bar` | 菜单栏 | メニューバー | Barre des menus | Barra de menús |
| `Hide menu bar icon` | 隐藏菜单栏图标 | メニューバーのアイコンを非表示 | Masquer l’icône de la barre des menus | Ocultar el icono de la barra de menús |
| `While the icon is hidden, open OpenContexts again from Applications or Spotlight to show Settings.` | 图标隐藏时，从“应用程序”文件夹或聚焦搜索再次打开 OpenContexts 即可显示设置。 | アイコンが非表示のときは、アプリケーションフォルダまたは Spotlight から OpenContexts をもう一度開くと設定が表示されます。 | Lorsque l’icône est masquée, rouvrez OpenContexts depuis Applications ou Spotlight pour afficher les réglages. | Con el icono oculto, vuelve a abrir OpenContexts desde Aplicaciones o Spotlight para ver los ajustes. |

`en.lproj` 的值与 key 相同。

### 4. 文档

- `README.md` 功能表,`Switcher display` 行之后加:
  `| Menu bar icon | Hide the icon in Settings → General. While it is hidden, open OpenContexts again from Applications or Spotlight to show Settings |`
- `README.zh-CN.md` 同一位置加:
  `| 菜单栏图标 | 在设置 → 通用中隐藏图标；隐藏时从“应用程序”文件夹或聚焦搜索再次打开 OpenContexts 即可显示设置 |`
- `README.md` 第 81 行(`You can open “Settings…” …`)末尾追加:
  ` If you hid the icon, open OpenContexts again from Applications or Spotlight to show Settings, then turn the icon back on to reach these menu items.`
- `README.zh-CN.md` 第 81 行末尾追加:
  `如果隐藏了图标，从“应用程序”文件夹或聚焦搜索再次打开 OpenContexts 即可显示设置，重新显示图标后就能使用这些菜单项。`

## 不做的事

- 不在设置页增加“退出”或“检查更新”按钮。
- 不改 `Panels.swift`、`ShortcutController.swift`、`WindowService.swift`、`website/`、`CHANGELOG.md`、`VERSION`。
- `Restore defaults` 只恢复快捷键,不动这个选项。
- 不动工作区里已有的未提交改动:`WindowService.swift` 的那一行、`.swiftformat`、`AGENTS.md`、`docs/plans/`。
- 不提交、不推送。

## 验证

这个功能的逻辑在 `OpenContexts` target,测试 target 覆盖不到,用 `--self-check` 做红绿验证。

按顺序执行,全部要通过,用直接的退出码判断:

1. 先加 `selfCheck` 断言和 `hideMenuBarIcon`、`setHideMenuBarIcon`,但 setter 暂时不写 `defaults`。运行 `swift build && .build/debug/OpenContexts --self-check`,确认失败原因是断言 `hidden menu bar icon must persist`,不是编译错误。
2. 补全实现后,再运行 `swift build && .build/debug/OpenContexts --self-check`,确认通过。这一步也检查五份语言文件的 key 一致性。
3. `swift test`
4. `.build/debug/OpenContexts --ui-self-check`:这一项曾偶发失败,报 `sidebar context menu lifecycle mismatch`。如果失败,要如实汇报报错原文和重跑结果,不要只报最后一次
5. `swiftformat Sources Tests --lint`

需要实机确认:

1. 默认状态下图标显示,选项未勾选。
2. 勾选后图标立即消失,设置窗口不关闭,`⌘Tab`、侧边栏、窗口搜索都正常。
3. 取消勾选后图标立即恢复,菜单项完整。
4. 隐藏状态下退出再启动,图标不出现,偏好保留。
5. 隐藏状态下再次打开应用,设置窗口显示在最前面;从 Finder、Spotlight、`open` 各试一次。
6. 设置窗口已经打开并被其他窗口盖住时,再次打开应用,设置窗口回到最前面。
7. 图标显示时再次打开应用,同样显示设置窗口。
8. General 页多了一行后,页面布局正常,五种语言下文字不被截断。
