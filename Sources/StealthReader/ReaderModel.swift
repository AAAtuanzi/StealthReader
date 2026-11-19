import AppKit
import CoreFoundation
import SwiftUI

enum ReaderTheme: Int, CaseIterable, Sendable {
    // Keep persisted IDs stable; ID 1 belonged to the removed soft-blue theme.
    case light = 0
    case dark = 2
    case deepSlate = 3
    case graphite = 4
    case indigo = 5
    case mist = 6

    var next: ReaderTheme {
        switch self {
        case .light: .dark
        case .dark: .deepSlate
        case .deepSlate: .graphite
        case .graphite: .indigo
        case .indigo: .mist
        case .mist: .light
        }
    }

    var backgroundColor: NSColor {
        switch self {
        case .light: .white
        case .dark: NSColor(srgbRed: 18 / 255, green: 19 / 255, blue: 20 / 255, alpha: 1)
        case .deepSlate: NSColor(srgbRed: 13 / 255, green: 17 / 255, blue: 22 / 255, alpha: 1)
        case .graphite: NSColor(srgbRed: 25 / 255, green: 29 / 255, blue: 36 / 255, alpha: 1)
        case .indigo: NSColor(srgbRed: 29 / 255, green: 31 / 255, blue: 46 / 255, alpha: 1)
        case .mist: NSColor(srgbRed: 247 / 255, green: 248 / 255, blue: 251 / 255, alpha: 1)
        }
    }

    var textColor: NSColor {
        switch self {
        case .light: NSColor(white: 0.12, alpha: 1)
        case .dark: NSColor(white: 0.86, alpha: 1)
        case .deepSlate: NSColor(srgbRed: 130 / 255, green: 140 / 255, blue: 157 / 255, alpha: 1)
        case .graphite: NSColor(srgbRed: 232 / 255, green: 234 / 255, blue: 239 / 255, alpha: 1)
        case .indigo: NSColor(srgbRed: 230 / 255, green: 232 / 255, blue: 239 / 255, alpha: 1)
        case .mist: NSColor(srgbRed: 23 / 255, green: 26 / 255, blue: 38 / 255, alpha: 1)
        }
    }

    func readingFont(at size: CGFloat) -> NSFont {
        if self == .indigo {
            // Let the text system resolve mixed scripts as it lays out visible text.
            // No per-character scan or restyling of a whole novel.
            let latin = NSFont(name: "Menlo-Regular", size: size)
                ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
            let chinese = NSFontDescriptor(name: "PingFangSC-Regular", size: size)
            let descriptor = latin.fontDescriptor.addingAttributes([.cascadeList: [chinese]])
            return NSFont(descriptor: descriptor, size: size) ?? latin
        }
        return NSFont(name: self == .graphite ? "PingFangSC-Regular" : "Songti SC", size: size)
            ?? NSFont.systemFont(ofSize: size)
    }

    var usesReferenceRendering: Bool { self == .graphite || self == .indigo }

    var fontSizeKey: String {
        switch self {
        case .graphite: "graphiteFontSize"
        case .indigo: "indigoFontSize"
        default: "fontSize"
        }
    }

    func savedFontSize() -> Double {
        let size = UserDefaults.standard.double(forKey: fontSizeKey)
        if size.isFinite && (10...48).contains(size) { return size }
        switch self {
        case .indigo: return 24
        case .graphite: return 20
        default: return 18
        }
    }
}

@MainActor
final class ReaderModel: ObservableObject {
    @Published var text = "把鼠标移到窗口内，然后点击“打开 TXT”开始阅读。\n\n鼠标移出窗口后，标题栏、边框和按钮会自动隐藏；移回来即可恢复。"
    @Published var documentName = "隐阅"
    @Published var theme: ReaderTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: "readerTheme")
            if oldValue != theme { fontSize = theme.savedFontSize() }
        }
    }
    @Published var fontSize: Double {
        didSet { UserDefaults.standard.set(fontSize, forKey: theme.fontSizeKey) }
    }
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published private(set) var textRevision = 0
    @Published private(set) var restoreLocation: Int?
    private var loadGeneration = UUID()
    private var currentFilePath: String?

    var minimumWindowSize: NSSize {
        ReaderWindowMetrics.minimumSize(font: theme.readingFont(at: fontSize))
    }

    init() {
        let defaults = UserDefaults.standard
        let initialTheme: ReaderTheme
        if defaults.object(forKey: "readerTheme") != nil {
            let savedValue = defaults.integer(forKey: "readerTheme")
            initialTheme = ReaderTheme(rawValue: savedValue) ?? .light
            if initialTheme.rawValue != savedValue {
                // Removed/invalid choices fall back to white without changing other saved themes.
                defaults.set(initialTheme.rawValue, forKey: "readerTheme")
            }
        } else {
            // Preserve the black/white choice made in versions before 1.3.
            initialTheme = (defaults.object(forKey: "isDark") as? Bool ?? false) ? .dark : .light
        }
        theme = initialTheme
        fontSize = initialTheme.savedFontSize()

        // Reopen the last book automatically. A missing or moved file is ignored.
        if let path = defaults.string(forKey: "lastFilePath"),
           FileManager.default.fileExists(atPath: path) {
            Task { [weak self] in
                self?.load(URL(fileURLWithPath: path))
            }
        }
    }

    func changeFontSize(by amount: Double) {
        fontSize = min(48, max(10, fontSize + amount))
    }

    func cycleTheme() {
        theme = theme.next
    }

    func saveReadingPosition(_ characterLocation: Int) {
        guard let currentFilePath else { return }
        let defaults = UserDefaults.standard
        var positions = defaults.dictionary(forKey: "readingPositions") as? [String: Int] ?? [:]
        positions[currentFilePath] = max(0, characterLocation)
        defaults.set(positions, forKey: "readingPositions")
    }

    func openTextFile() {
        WindowChromeController.shared.suspendAutoHide = true

        let panel = NSOpenPanel()
        panel.title = "选择 TXT 小说"
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        panel.begin { [weak self] response in
            Task { @MainActor in
                WindowChromeController.shared.suspendAutoHide = false
                guard response == .OK, let url = panel.url else { return }
                self?.load(url)
            }
        }
    }

    private func load(_ url: URL) {
        let generation = UUID()
        loadGeneration = generation
        isLoading = true

        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                do {
                    let data = try Data(contentsOf: url, options: .mappedIfSafe)
                    guard let decoded = Self.decode(data) else {
                        return LoadOutcome.failure(ReaderError.unsupportedEncoding.localizedDescription)
                    }
                    return LoadOutcome.success(
                        text: decoded,
                        name: url.deletingPathExtension().lastPathComponent
                    )
                } catch {
                    return LoadOutcome.failure(error.localizedDescription)
                }
            }.value

            guard loadGeneration == generation else { return }
            isLoading = false
            switch outcome {
            case let .success(decoded, name):
                let path = url.standardizedFileURL.path
                currentFilePath = path
                UserDefaults.standard.set(path, forKey: "lastFilePath")
                let positions = UserDefaults.standard.dictionary(forKey: "readingPositions")
                    as? [String: Int] ?? [:]
                restoreLocation = positions[path]
                text = decoded
                documentName = name
                WindowChromeController.shared.window?.title = name
                // Publish the revision last so text and restore position arrive together.
                textRevision += 1
            case let .failure(message):
                errorMessage = "无法打开这个文件：\(message)"
            }
        }
    }

    nonisolated private static func decode(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }

        let bytes = data.prefix(2)
        if bytes.elementsEqual([0xFF, 0xFE]),
           let utf16LE = String(data: data, encoding: .utf16LittleEndian) {
            return utf16LE
        }
        if bytes.elementsEqual([0xFE, 0xFF]),
           let utf16BE = String(data: data, encoding: .utf16BigEndian) {
            return utf16BE
        }

        let legacyEncodings: [String.Encoding] = [
            chineseEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)),
            chineseEncoding(CFStringEncoding(CFStringEncodings.GBK_95.rawValue)),
            chineseEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue))
        ]

        for encoding in legacyEncodings {
            if let string = String(data: data, encoding: encoding) {
                return string
            }
        }
        return nil
    }

    nonisolated private static func chineseEncoding(_ value: CFStringEncoding) -> String.Encoding {
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(value))
    }
}

private enum LoadOutcome: Sendable {
    case success(text: String, name: String)
    case failure(String)
}

private enum ReaderError: LocalizedError {
    case unsupportedEncoding

    var errorDescription: String? {
        "无法识别文本编码。请将文件另存为 UTF-8、UTF-16、GBK/GB18030 或 Big5。"
    }
}
