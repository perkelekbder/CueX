import SwiftUI

/// Neutral surfaces and blue controls inspired by the supplied Logic Pro reference.
enum LogicTheme {
    static let background = Color(white: 0.19)
    static let setlist = Color(white: 0.33)
    static let row = Color(white: 0.36)
    static let selectedRow = Color(white: 0.46)
    static let panel = Color(white: 0.27)
    static let timing = Color(white: 0.22)
    static let footer = Color(white: 0.24)
    static let text = Color(white: 0.96)
    static let secondaryText = Color(white: 0.76)
    static let divider = Color.black.opacity(0.3)
    static let blue = Color(red: 0.15, green: 0.46, blue: 0.75)
    static let green = Color(red: 0.24, green: 0.85, blue: 0.17)
    static let red = Color(red: 0.91, green: 0.22, blue: 0.18)
    static let amber = Color(red: 1, green: 0.71, blue: 0.25)
    static let toolbar = LinearGradient(
        colors: [Color(white: 0.39), Color(white: 0.30)],
        startPoint: .top, endPoint: .bottom
    )
}

struct LogicButtonStyle: ButtonStyle {
    var tint: Color?
    var cornerRadius: CGFloat = 8
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        configuration.label
            .foregroundStyle(LogicTheme.text)
            .background {
                shape.fill(LinearGradient(
                    colors: tint.map { [$0, $0.opacity(0.8)] }
                        ?? [Color(white: 0.43), Color(white: 0.33)],
                    startPoint: .top, endPoint: .bottom
                ))
            }
            .overlay {
                shape.strokeBorder(.white.opacity(configuration.isPressed ? 0.08 : 0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
            .brightness(configuration.isPressed ? -0.08 : 0)
            .opacity(isEnabled ? 1 : 0.4)
    }
}
