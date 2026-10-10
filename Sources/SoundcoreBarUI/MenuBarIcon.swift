import SwiftUI

/// What the menu bar shows: an SF Symbol, or a short piece of text such as an emoji.
/// Stored in user defaults as "symbol:<name>" or "text:<text>".
public enum MenuBarIcon: Hashable, Sendable {
    case symbol(String)
    case text(String)

    public static let storageKey = "menuBarIcon"
    public static let `default` = MenuBarIcon.symbol("hare.fill")
    /// Custom text is cut to this many characters so it fits in the menu bar.
    static let maxTextLength = 3

    static let symbolChoices: [MenuBarIcon] = [
        "hare.fill", "headphones", "earbuds", "ear.fill", "waveform", "music.note",
        "pawprint.fill", "carrot.fill", "cat.fill", "sparkles", "moon.stars.fill", "heart.fill",
    ].map(MenuBarIcon.symbol)

    static let emojiChoices: [MenuBarIcon] = [
        "🐰", "🐇", "🎧", "🦋", "🥕", "🌸", "✨", "🌙", "💜", "🎵", "🍓", "🐱",
    ].map(MenuBarIcon.text)

    public init(rawValue: String) {
        if rawValue.hasPrefix("symbol:") {
            self = .symbol(String(rawValue.dropFirst("symbol:".count)))
        } else if rawValue.hasPrefix("text:"), rawValue.count > "text:".count {
            self = .text(String(rawValue.dropFirst("text:".count)))
        } else {
            self = .default
        }
    }

    public var rawValue: String {
        switch self {
        case .symbol(let name): "symbol:" + name
        case .text(let text): "text:" + text
        }
    }

    /// Custom text from the user, or nil if it is blank.
    static func custom(_ input: String) -> MenuBarIcon? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : .text(String(trimmed.prefix(maxTextLength)))
    }

    var accessibilityName: String {
        switch self {
        case .symbol(let name): name.replacingOccurrences(of: ".", with: " ")
        case .text(let text): text
        }
    }

    /// The icon as it appears in the menu bar.
    @ViewBuilder public var label: some View {
        switch self {
        case .symbol(let name): Image(systemName: name)
        case .text(let text): Text(text)
        }
    }
}
