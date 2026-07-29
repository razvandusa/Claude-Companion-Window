import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global shortcut that shows or hides the companion window.
    ///
    /// Defaults to ⌥Space. Users rebind it from Settings; `KeyboardShortcuts`
    /// persists the override in `UserDefaults` under this name.
    static let toggleCompanion = Self(
        "toggleCompanion",
        default: .init(.space, modifiers: [.option])
    )
}
