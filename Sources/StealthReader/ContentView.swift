import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var reader: ReaderModel
    @State private var chromeIsHidden = false
    @State private var trackingMenuCount = 0

    private var background: Color { Color(nsColor: reader.theme.backgroundColor) }
    private var foreground: Color { Color(nsColor: reader.theme.textColor) }

    var body: some View {
        ZStack(alignment: .top) {
            background.ignoresSafeArea()

            LongTextView(
                text: reader.text,
                revision: reader.textRevision,
                fontSize: reader.fontSize,
                theme: reader.theme,
                chromeIsHidden: chromeIsHidden,
                restoreLocation: reader.restoreLocation,
                onPositionChange: { reader.saveReadingPosition($0) }
            )

            MouseTrackingView(
                onMove: { point, size in
                    updateChrome(for: point, in: size)
                },
                onExit: { setChromeHidden(true) }
            )
            .allowsHitTesting(false)
        }
        .overlay {
            if reader.isLoading {
                ProgressView("正在打开 TXT…")
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .overlay(alignment: .topLeading) {
            if !chromeIsHidden {
                controls
                    .transition(.opacity)
            }
        }
        .background(WindowReader { window in
            WindowChromeController.shared.attach(window, minimumContentSize: reader.minimumWindowSize)
            window.title = reader.documentName
        })
        .animation(.easeOut(duration: 0.14), value: chromeIsHidden)
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
            trackingMenuCount += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
            trackingMenuCount = max(0, trackingMenuCount - 1)
            if trackingMenuCount == 0 { hideChromeIfPointerIsOutside() }
        }
        .alert("打开失败", isPresented: Binding(
            get: { reader.errorMessage != nil },
            set: { if !$0 { reader.errorMessage = nil } }
        )) {
            Button("好") { reader.errorMessage = nil }
        } message: {
            Text(reader.errorMessage ?? "未知错误")
        }
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            fullControls
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule())
                .padding(.top, 14)
                .padding(.leading, 12)
            compactControls
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.regularMaterial, in: Capsule())
                .padding(.horizontal, 4)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(foreground)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var compactControls: some View {
        Menu {
            Button("打开 TXT…") { reader.openTextFile() }
                .disabled(reader.isLoading)
            Button("搜索文字…") {
                NotificationCenter.default.post(name: .stealthReaderShowSearch, object: nil)
            }
            Divider()
            Button("减小字体（当前 \(Int(reader.fontSize))）") { reader.changeFontSize(by: -1) }
            Button("增大字体") { reader.changeFontSize(by: 1) }
            Divider()
            Menu("阅读配色") {
                ForEach(ReaderTheme.allCases, id: \.rawValue) { theme in
                    Toggle(isOn: Binding(
                        get: { reader.theme == theme },
                        set: { if $0 { reader.theme = theme } }
                    )) {
                        Label {
                            Text(theme.displayName)
                        } icon: {
                            Image(nsImage: theme.menuPreview).renderingMode(.original)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: 20, height: 18)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("阅读操作：打开、搜索、字号、配色")
    }

    private var fullControls: some View {
        HStack(spacing: 12) {
            Button {
                reader.openTextFile()
            } label: {
                Label("打开 TXT", systemImage: "doc.text")
            }
            .disabled(reader.isLoading)

            Divider().frame(height: 18)

            Button {
                NotificationCenter.default.post(name: .stealthReaderShowSearch, object: nil)
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .help("搜索文字（⌘F）")

            Divider().frame(height: 18)

            Button { reader.changeFontSize(by: -1) } label: {
                Image(systemName: "textformat.size.smaller")
            }
            .help("减小字体")

            Text("\(Int(reader.fontSize))")
                .font(.system(.caption, design: .monospaced))
                .frame(width: 24)

            Button { reader.changeFontSize(by: 1) } label: {
                Image(systemName: "textformat.size.larger")
            }
            .help("增大字体")

            Divider().frame(height: 18)

            ThemeMenuButton(
                selectedTheme: reader.theme,
                onSelect: { reader.theme = $0 },
                onClose: hideChromeIfPointerIsOutside
            )
            .frame(width: 24, height: 22)
        }
    }

    private func updateChrome(for point: CGPoint, in size: CGSize) {
        guard trackingMenuCount == 0, !WindowChromeController.shared.suspendAutoHide else { return }

        // Hidden: only the small top-left corner wakes the controls.
        // Visible: keep them available while the pointer is over the title/controls strip.
        let activeWidth = chromeIsHidden ? 48.0 : min(410.0, size.width)
        let activeHeight = chromeIsHidden ? 48.0 : min(88.0, size.height)
        let isInTopLeft = point.x >= 0
            && point.x <= activeWidth
            && point.y >= size.height - activeHeight
            && point.y <= size.height

        setChromeHidden(!isInTopLeft)
    }

    private func setChromeHidden(_ hidden: Bool) {
        guard trackingMenuCount == 0, !WindowChromeController.shared.suspendAutoHide else { return }
        chromeIsHidden = hidden
        WindowChromeController.shared.setHidden(hidden)
    }

    private func hideChromeIfPointerIsOutside() {
        if let window = WindowChromeController.shared.window,
           !window.frame.contains(NSEvent.mouseLocation) {
            setChromeHidden(true)
        }
    }
}
