import SwiftUI

@main
struct StealthReaderApp: App {
    @NSApplicationDelegateAdaptor(ReaderAppDelegate.self) private var appDelegate
    @StateObject private var reader = ReaderModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(reader)
                .frame(minWidth: reader.minimumWindowSize.width,
                       minHeight: ReaderWindowMetrics.minimumHeight)
        }
        .defaultSize(width: 720, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开 TXT…") { reader.openTextFile() }
                    .keyboardShortcut("o", modifiers: .command)
            }

            CommandMenu("阅读") {
                Button("搜索文字…") {
                    NotificationCenter.default.post(name: .stealthReaderShowSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
                Divider()
                Button("增大字体") { reader.changeFontSize(by: 1) }
                    .keyboardShortcut("+", modifiers: .command)
                Button("减小字体") { reader.changeFontSize(by: -1) }
                    .keyboardShortcut("-", modifiers: .command)
                Divider()
                Button("切换阅读配色") { reader.cycleTheme() }
                    .keyboardShortcut("/", modifiers: .command)
                Button("石墨灰（截图样式）") { reader.theme = .graphite }
                Button("深靛灰") { reader.theme = .indigo }
            }
        }
    }
}
