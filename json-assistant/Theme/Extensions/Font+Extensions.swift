import SwiftUI

#if os(macOS)
import AppKit
private typealias UXFont = NSFont
#else
import UIKit
private typealias UXFont = UIFont
#endif

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
        let preferredFonts = ["Inter", "SF Pro Text"]
        for name in preferredFonts {
            if UXFont(name: name, size: size) != nil {
                return Font.custom(name, size: size)
            }
        }
        return Font.system(size: size, weight: .regular, design: .default)
    }
}
