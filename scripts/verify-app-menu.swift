import AppKit

@MainActor
private final class MenuActions: NSObject {
    var quitCount = 0
    var hideCount = 0
    var openCount = 0
    var searchCount = 0
    @objc func terminate(_ sender: Any?) { quitCount += 1 }
    @objc func hide(_ sender: Any?) { hideCount += 1 }
    @objc func openDocument(_ sender: Any?) { openCount += 1 }
    @objc func search(_ sender: Any?) { searchCount += 1 }
}

@main
struct AppMenuCheck {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        let actions = MenuActions()
        let main = NSMenu()
        let titles = ["隐阅", "文件", "编辑", "显示", "阅读", "窗口", "帮助"]
        for title in titles {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = NSMenu(title: title)
            item.submenu!.autoenablesItems = false
            main.addItem(item)
        }
        func add(_ index: Int, _ title: String, _ action: Selector, _ key: String) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = actions
            item.keyEquivalentModifierMask = .command
            main.items[index].submenu!.addItem(item)
        }
        add(0, "退出隐阅", #selector(MenuActions.terminate(_:)), "q")
        add(0, "隐藏隐阅", #selector(MenuActions.hide(_:)), "h")
        add(1, "打开 TXT", #selector(MenuActions.openDocument(_:)), "o")
        add(4, "搜索文字", #selector(MenuActions.search(_:)), "f")
        let originalItems = main.items
        ReaderAppDelegate.hideApplicationName(in: main)
        ReaderAppDelegate.hideApplicationName(in: main)
        precondition(main.items == originalItems)
        precondition(main.items.allSatisfy { !$0.isHidden })
        precondition(main.items.dropFirst().map(\.title) == Array(titles.dropFirst()))
        precondition(main.items[0].title == "\u{200B}")
        precondition(main.items[0].attributedTitle?.string == "\u{200B}")
        precondition(main.items[0].submenu!.title == "\u{200B}")
        precondition(main.items[0].submenu!.items.allSatisfy {
            !$0.isHiddenOrHasHiddenAncestor && !$0.allowsKeyEquivalentWhenHidden
        })
        precondition(!main.items[1].allowsKeyEquivalentWhenHidden)

        for (key, code) in [("q", 12), ("h", 4), ("o", 31), ("f", 3)] {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                        timestamp: 0, windowNumber: 0, context: nil, characters: key,
                                        charactersIgnoringModifiers: key, isARepeat: false,
                                        keyCode: UInt16(code))!
            precondition(main.performKeyEquivalent(with: event), "Shortcut failed: command-\(key)")
        }
        precondition(actions.quitCount == 1 && actions.hideCount == 1)
        precondition(actions.openCount == 1 && actions.searchCount == 1)
        let unrelated = NSMenu()
        unrelated.addItem(withTitle: "文件", action: nil, keyEquivalent: "")
        ReaderAppDelegate.hideApplicationName(in: unrelated)
        precondition(!unrelated.items[0].isHidden)
        ReaderAppDelegate.hideApplicationName(in: nil)
        print("PASS: only app name blank; all menu items preserved; command-Q/H/O/F dispatch correctly")
    }
}
