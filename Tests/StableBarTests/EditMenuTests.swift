import AppKit
import Testing
@testable import StableBar

@MainActor @Test func editMenuGivesTextFieldsTheClipboardShortcuts() {
    let items = EditMenu.make().items.flatMap { $0.submenu?.items ?? [] }
    let shortcuts = Dictionary(uniqueKeysWithValues: items.map { ($0.keyEquivalent, $0.action) })
    #expect(shortcuts == [
        "x": #selector(NSText.cut(_:)),
        "c": #selector(NSText.copy(_:)),
        "v": #selector(NSText.paste(_:)),
        "a": #selector(NSText.selectAll(_:)),
    ])
    #expect(items.allSatisfy { $0.keyEquivalentModifierMask == .command })
}
