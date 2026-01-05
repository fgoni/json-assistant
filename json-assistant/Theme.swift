import SwiftUI

#if os(macOS)
import AppKit
private typealias UXFont = NSFont
#else
import UIKit
private typealias UXFont = UIFont
#endif

extension Color {
    init(hex: String, alpha: Double = 1.0) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        
        let r, g, b: Double
        switch cleaned.count {
        case 6:
            r = Double((value >> 16) & 0xFF) / 255.0
            g = Double((value >> 8) & 0xFF) / 255.0
            b = Double(value & 0xFF) / 255.0
        case 3:
            r = Double((value >> 8) & 0xF) / 15.0
            g = Double((value >> 4) & 0xF) / 15.0
            b = Double(value & 0xF) / 15.0
        default:
            r = 1.0
            g = 1.0
            b = 1.0
        }
        
        self.init(red: r, green: g, blue: b, opacity: alpha)
    }
}

struct ThemePalette {
    let background: Color
    let surface: Color
    let text: Color
    let muted: Color
    let placeholderText: Color  // Semantic color for input placeholders
    let buttonText: Color       // Semantic color for button text
    let accentButtonText: Color // Semantic color for text on accent-colored buttons
    let key: Color
    let string: Color
    let number: Color
    let boolTrue: Color
    let boolFalse: Color
    let null: Color
    let punctuation: Color
    let accent: Color
    let selection: Color
    
    static func palette(for scheme: ColorScheme) -> ThemePalette {
        scheme == .dark ? .dark : .light
    }
    
    static let dark = ThemePalette(
        background: Color(hex: "#0B0F14"),
        surface: Color(hex: "#111827"),
        text: Color(hex: "#E5E7EB"),
        muted: Color(hex: "#9CA3AF"),
        placeholderText: Color(hex: "#F3F4F6"),  // Very light gray, close to white for visibility
        buttonText: Color(hex: "#F3F4F6"),       // Same whiter color for buttons
        accentButtonText: Color(hex: "#FFFFFF"), // White text for accent-colored buttons
        key: Color(hex: "#93C5FD"),
        string: Color(hex: "#86EFAC"),
        number: Color(hex: "#F59E0B"),
        boolTrue: Color(hex: "#34D399"),
        boolFalse: Color(hex: "#F87171"),
        null: Color(hex: "#A78BFA"),
        punctuation: Color(hex: "#94A3B8"),
        accent: Color(hex: "#60A5FA"),
        selection: Color(hex: "#1F2937")
    )
    
    static let light = ThemePalette(
        background: Color(hex: "#F8FAFC"),
        surface: Color(hex: "#FFFFFF"),
        text: Color(hex: "#0F172A"),
        muted: Color(hex: "#475569"),
        placeholderText: Color(hex: "#6B7280"),  // Medium gray for light mode placeholders
        buttonText: Color(hex: "#0F172A"),        // Dark text for light mode buttons
        accentButtonText: Color(hex: "#FFFFFF"), // White text for accent-colored buttons
        key: Color(hex: "#1D4ED8"),
        string: Color(hex: "#B45309"),
        number: Color(hex: "#7C3AED"),
        boolTrue: Color(hex: "#047857"),
        boolFalse: Color(hex: "#B91C1C"),
        null: Color(hex: "#64748B"),
        punctuation: Color(hex: "#94A3B8"),
        accent: Color(hex: "#2563EB"),
        selection: Color(hex: "#DBEAFE")
    )
}

extension Font {
    static func themedCode(size: CGFloat = 13) -> Font {
        let preferredFonts = ["JetBrains Mono", "SFMono-Regular", "Fira Code", "Menlo", "Consolas", "Liberation Mono"]
        for name in preferredFonts {
            if UXFont(name: name, size: size) != nil {
                return Font.custom(name, size: size)
            }
        }
        return Font.system(size: size, weight: .regular, design: .monospaced)
    }

    static func themedUI(size: CGFloat = 13) -> Font {
        let baseSize = UserDefaults.standard.double(forKey: ThemeSettings.uiFontSizeDefaultsKey)
        let resolvedBaseSize = baseSize > 0 ? baseSize : ThemeSettings.defaultUIFontSize
        let scale = CGFloat(resolvedBaseSize / ThemeSettings.defaultUIFontSize)
        let scaledSize = max(1, size * scale)

        let preferredFonts = ["Inter", "SF Pro Text"]
        for name in preferredFonts {
            if UXFont(name: name, size: scaledSize) != nil {
                return Font.custom(name, size: scaledSize)
            }
        }
        return Font.system(size: scaledSize, weight: .regular, design: .default)
    }
}

// MARK: - Theme Settings
enum ThemeMode: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

class ThemeSettings: ObservableObject {
    static let defaultUIFontSize: Double = 13
    static let defaultRequestJSONFontSize: Double = 13
    static let defaultFormattedJSONFontSize: Double = 13

    static let minimumFontSize: Double = 9
    static let maximumFontSize: Double = 28

    static let uiFontSizeDefaultsKey = "uiFontSize"
    static let requestJSONFontSizeDefaultsKey = "requestJSONFontSize"
    static let formattedJSONFontSizeDefaultsKey = "formattedJSONFontSize"
    static let requestJSONWordWrapDefaultsKey = "requestJSONWordWrap"
    static let formattedJSONWordWrapDefaultsKey = "formattedJSONWordWrap"

    @Published var selectedTheme: ThemeMode {
        didSet {
            UserDefaults.standard.set(selectedTheme.rawValue, forKey: "themeMode")
        }
    }

    @Published var uiFontSize: Double {
        didSet {
            let clamped = Self.clamp(uiFontSize)
            guard uiFontSize != clamped else {
                UserDefaults.standard.set(uiFontSize, forKey: Self.uiFontSizeDefaultsKey)
                return
            }
            uiFontSize = clamped
        }
    }

    @Published var requestJSONFontSize: Double {
        didSet {
            let clamped = Self.clamp(requestJSONFontSize)
            guard requestJSONFontSize != clamped else {
                UserDefaults.standard.set(requestJSONFontSize, forKey: Self.requestJSONFontSizeDefaultsKey)
                return
            }
            requestJSONFontSize = clamped
        }
    }

    @Published var formattedJSONFontSize: Double {
        didSet {
            let clamped = Self.clamp(formattedJSONFontSize)
            guard formattedJSONFontSize != clamped else {
                UserDefaults.standard.set(formattedJSONFontSize, forKey: Self.formattedJSONFontSizeDefaultsKey)
                return
            }
            formattedJSONFontSize = clamped
        }
    }

    @Published var requestJSONWordWrap: Bool {
        didSet {
            UserDefaults.standard.set(requestJSONWordWrap, forKey: Self.requestJSONWordWrapDefaultsKey)
        }
    }

    @Published var formattedJSONWordWrap: Bool {
        didSet {
            UserDefaults.standard.set(formattedJSONWordWrap, forKey: Self.formattedJSONWordWrapDefaultsKey)
        }
    }

    @Published var showSettingsPanel = false

    init() {
        let savedTheme = UserDefaults.standard.string(forKey: "themeMode") ?? ThemeMode.system.rawValue
        self.selectedTheme = ThemeMode(rawValue: savedTheme) ?? .system

        let savedUIFontSize = UserDefaults.standard.double(forKey: Self.uiFontSizeDefaultsKey)
        self.uiFontSize = savedUIFontSize > 0 ? Self.clamp(savedUIFontSize) : Self.defaultUIFontSize

        let savedRequestFontSize = UserDefaults.standard.double(forKey: Self.requestJSONFontSizeDefaultsKey)
        self.requestJSONFontSize = savedRequestFontSize > 0 ? Self.clamp(savedRequestFontSize) : Self.defaultRequestJSONFontSize

        let savedFormattedFontSize = UserDefaults.standard.double(forKey: Self.formattedJSONFontSizeDefaultsKey)
        self.formattedJSONFontSize = savedFormattedFontSize > 0 ? Self.clamp(savedFormattedFontSize) : Self.defaultFormattedJSONFontSize

        // Initialize word-wrap settings (default to true for better UX)
        self.requestJSONWordWrap = UserDefaults.standard.object(forKey: Self.requestJSONWordWrapDefaultsKey) as? Bool ?? true
        self.formattedJSONWordWrap = UserDefaults.standard.object(forKey: Self.formattedJSONWordWrapDefaultsKey) as? Bool ?? true
    }

    func increaseRequestJSONFontSize() {
        requestJSONFontSize = Self.clamp(requestJSONFontSize + 1)
    }

    func decreaseRequestJSONFontSize() {
        requestJSONFontSize = Self.clamp(requestJSONFontSize - 1)
    }

    func increaseFormattedJSONFontSize() {
        formattedJSONFontSize = Self.clamp(formattedJSONFontSize + 1)
    }

    func decreaseFormattedJSONFontSize() {
        formattedJSONFontSize = Self.clamp(formattedJSONFontSize - 1)
    }

    func resetFontSizes() {
        uiFontSize = Self.defaultUIFontSize
        requestJSONFontSize = Self.defaultRequestJSONFontSize
        formattedJSONFontSize = Self.defaultFormattedJSONFontSize
    }

    /// Get the effective color scheme based on selected theme and system preference
    func getColorScheme(systemScheme: ColorScheme) -> ColorScheme? {
        switch selectedTheme {
        case .system:
            return nil  // Let the system decide
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, minimumFontSize), maximumFontSize)
    }
}
