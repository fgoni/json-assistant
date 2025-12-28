import SwiftUI

// MARK: - Typography
struct Typography {
    // UI Font sizes
    static let ui8: CGFloat = 8
    static let ui10: CGFloat = 10
    static let ui11: CGFloat = 11
    static let ui12: CGFloat = 12
    static let ui13: CGFloat = 13
    static let ui14: CGFloat = 14

    // Font weights
    struct Weight {
        static let regular = Font.Weight.regular
        static let semibold = Font.Weight.semibold
        static let bold = Font.Weight.bold
    }
}

// MARK: - Spacing
struct Spacing {
    static let xs: CGFloat = 4      // Extra small
    static let sm: CGFloat = 6      // Small
    static let md: CGFloat = 8      // Medium
    static let lg: CGFloat = 12     // Large
    static let xl: CGFloat = 16     // Extra large
    static let xxl: CGFloat = 20    // Double extra large
    static let xxxl: CGFloat = 24   // Triple extra large
}

// MARK: - Padding
struct Padding {
    // Vertical padding presets
    static let buttonVertical: CGFloat = 6
    static let inputVertical: CGFloat = 8
    static let rowVertical: CGFloat = 10
    static let sectionVertical: CGFloat = 12

    // Horizontal padding presets
    static let buttonHorizontal: CGFloat = 12
    static let inputHorizontal: CGFloat = 10
    static let panelHorizontal: CGFloat = 12
    static let screenHorizontal: CGFloat = 20

    // Panel paddings
    static let screenPadding: EdgeInsets = EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20)
    static let panelPadding: EdgeInsets = EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
    static let sheetPadding: EdgeInsets = EdgeInsets(top: 24, leading: 24, bottom: 24, trailing: 24)
}

// MARK: - Corner Radius
struct CornerRadius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 10
    static let large: CGFloat = 12
    static let extraLarge: CGFloat = 20
}

// MARK: - Opacity
struct Opacity {
    static let disabled: CGFloat = 0.5
    static let secondary: CGFloat = 0.6
    static let tertiary: CGFloat = 0.7
    static let hover: CGFloat = 0.75
    static let muted: CGFloat = 0.85
    static let light: CGFloat = 0.12
}

// MARK: - Button Styles
struct ButtonStyles {
    struct Primary {
        static let cornerRadius = CornerRadius.small
        static let verticalPadding = Padding.buttonVertical
        static let horizontalPadding = Padding.buttonHorizontal
    }

    struct Secondary {
        static let cornerRadius = CornerRadius.small
        static let verticalPadding = Padding.buttonVertical
        static let horizontalPadding = Padding.buttonHorizontal
    }
}

// MARK: - Custom TextFieldStyle with Better Placeholder Visibility
struct ThemedTextFieldStyle: TextFieldStyle {
    let palette: ThemePalette

    func _body(configuration: TextField<Self.Label>) -> some View {
        configuration
            .tint(palette.accent)
    }
}

extension View {
    func themedTextFieldStyle(_ palette: ThemePalette) -> some View {
        self.textFieldStyle(ThemedTextFieldStyle(palette: palette))
    }
}
