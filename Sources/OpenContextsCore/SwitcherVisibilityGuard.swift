/// Decides how a switcher session recovers when its panel was ordered front but never reached the screen.
///
/// The window server can leave a panel ordered in without placing it on any Space. The session
/// must not keep capturing the keyboard while nothing is visible.
public struct SwitcherVisibilityGuard: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        /// The panel is on screen; the session continues.
        case keep
        /// Replace the panel with a new one, show it and check once more.
        case rebuildAndRetry
        /// A new panel did not reach the screen either; end the session and release the keyboard.
        case cancel
    }

    public private(set) var didRebuild = false

    public init() {}

    /// - Parameters:
    ///   - onScreen: Target panels the window server reports on screen.
    ///   - expected: Panels the session ordered front, one per target display.
    public mutating func resolve(onScreen: Int, expected: Int) -> Action {
        if expected > 0, onScreen >= expected { return .keep }
        if !didRebuild {
            didRebuild = true
            return .rebuildAndRetry
        }
        // One visible panel is enough for the user to see what the keyboard controls.
        return onScreen > 0 ? .keep : .cancel
    }
}
