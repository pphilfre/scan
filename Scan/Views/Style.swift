import SwiftUI

enum FolioStyle {
    static let ink = Color(light: UIColor(red: 0.18, green: 0.29, blue: 0.25, alpha: 1), dark: UIColor(red: 0.68, green: 0.83, blue: 0.73, alpha: 1))
    static let paper = Color(uiColor: .systemGroupedBackground)
    static let colors = ["sage", "blue", "clay", "plum", "sand", "graphite"]
    static let symbols = ["book.closed", "function", "atom", "chart.line.uptrend.xyaxis", "leaf", "lightbulb", "pencil", "globe.europe.africa"]
    static func color(_ name: String) -> Color {
        switch name {
        case "blue": Color(red: 0.33, green: 0.47, blue: 0.62)
        case "clay": Color(red: 0.69, green: 0.39, blue: 0.30)
        case "plum": Color(red: 0.48, green: 0.36, blue: 0.51)
        case "sand": Color(red: 0.67, green: 0.54, blue: 0.34)
        case "graphite": Color(red: 0.29, green: 0.32, blue: 0.35)
        default: Color(red: 0.34, green: 0.48, blue: 0.39)
        }
    }
    @MainActor static func haptic() { UISelectionFeedbackGenerator().selectionChanged() }
}

extension Color {
    init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

struct CoverAppearance {
    var title: String
    var color: String
    var secondColor: String
    var symbol: String
    var style: String
    var spine: String
    var texture: Double
    init(_ book: Notebook) {
        title = book.title; color = book.colorName; secondColor = book.gradientColorName
        symbol = book.symbol; style = book.coverStyle; spine = book.spineLabel; texture = book.textureStrength
    }
    init(title: String, color: String, secondColor: String, symbol: String, style: String, spine: String, texture: Double) {
        self.title = title; self.color = color; self.secondColor = secondColor
        self.symbol = symbol; self.style = style; self.spine = spine; self.texture = texture
    }
}

struct BookCover: View {
    let appearance: CoverAppearance
    var tabs: [String] = []
    init(book: Notebook) { appearance = CoverAppearance(book); tabs = Array(book.activeSections.prefix(6).map(\.colorName)) }
    init(appearance: CoverAppearance) { self.appearance = appearance }
    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 7).fill(LinearGradient(colors: [FolioStyle.color(appearance.color), FolioStyle.color(appearance.style == "gradient" ? appearance.secondColor : appearance.color).opacity(0.88)], startPoint: .topLeading, endPoint: .bottomTrailing))
            if ["linen", "paper", "ruled"].contains(appearance.style) {
                Canvas { context, size in
                    var path = Path()
                    let step: CGFloat = appearance.style == "ruled" ? 18 : 5
                    for y in stride(from: CGFloat(0), through: size.height, by: step) {
                        path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    if appearance.style == "linen" {
                        for x in stride(from: CGFloat(0), through: size.width, by: step) {
                            path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
                        }
                    }
                    context.stroke(path, with: .color(.white.opacity(appearance.texture)), lineWidth: 0.5)
                }.clipShape(RoundedRectangle(cornerRadius: 7))
            }
            Rectangle().fill(.black.opacity(0.14)).frame(width: 13).padding(.leading, 5)
            if !appearance.spine.isEmpty {
                Text(appearance.spine.uppercased()).font(.system(size: 7, weight: .medium)).tracking(1)
                    .rotationEffect(.degrees(-90)).fixedSize().frame(width: 16).foregroundStyle(.white.opacity(0.8)).padding(.leading, 4)
            }
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: appearance.symbol).font(.title2.weight(.light))
                Spacer(minLength: 8)
                Text(appearance.title).font(.system(.title3, design: .serif, weight: .medium)).lineLimit(3).minimumScaleFactor(0.7)
            }.foregroundStyle(.white).padding(20).padding(.leading, 8)
        }
        .aspectRatio(0.73, contentMode: .fit)
        .overlay(alignment: .trailing) {
            VStack(spacing: 5) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { _, color in
                    RoundedRectangle(cornerRadius: 2).fill(FolioStyle.color(color)).frame(width: 9, height: 15)
                        .overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.3)).frame(width: 1) }
                }
            }.offset(x: 5).padding(.vertical, 14).accessibilityHidden(true)
        }
        .shadow(color: .black.opacity(0.13), radius: 8, x: 2, y: 5)
        .accessibilityElement(children: .ignore).accessibilityLabel(appearance.title)
    }
}

struct HighlightedText: View {
    let value: String
    let query: String
    var body: some View { Text(highlighted) }
    private var highlighted: AttributedString {
        var result = AttributedString(value)
        guard !query.isEmpty else { return result }
        var start = result.startIndex
        while start < result.endIndex,
              let range = result[start...].range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) {
            result[range].backgroundColor = .yellow.opacity(0.4)
            start = range.upperBound
        }
        return result
    }
}
