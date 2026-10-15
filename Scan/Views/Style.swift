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

struct BookCover: View {
    let book: Notebook
    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 8).fill(FolioStyle.color(book.colorName).gradient)
            if book.coverStyle == "ruled" {
                VStack(spacing: 17) {
                    ForEach(0..<10, id: \.self) { _ in Rectangle().fill(.white.opacity(0.07)).frame(height: 1) }
                }.padding(.horizontal, 15)
            }
            Rectangle().fill(.black.opacity(0.13)).frame(width: 10).padding(.leading, 6)
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: book.symbol).font(.title2.weight(.light))
                Spacer()
                Text(book.title).font(.system(.title3, design: .serif, weight: .medium)).lineLimit(3)
                Rectangle().fill(.white.opacity(0.45)).frame(width: 28, height: 1)
                Text("F O L I O").font(.system(size: 8, weight: .semibold))
            }.foregroundStyle(.white).padding(22).padding(.leading, 4)
        }
        .aspectRatio(0.73, contentMode: .fit)
        .overlay(alignment: .trailing) { RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.28)).frame(width: 3).padding(.vertical, 6).padding(.trailing, 3) }
        .shadow(color: FolioStyle.color(book.colorName).opacity(0.22), radius: 12, x: 0, y: 8)
        .accessibilityElement(children: .ignore).accessibilityLabel(book.title)
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
