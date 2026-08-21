import Foundation

/// One contiguous flashlight state in an International Morse transmission.
public struct MorsePulse: Sendable, Equatable, Codable {
    public let isOn: Bool
    public let units: Int

    public init(isOn: Bool, units: Int) {
        self.isOn = isOn
        self.units = units
    }
}

/// A deterministic Morse encoder shared by the shipping tool and the eval harness.
///
/// Timing follows the International Morse standard:
/// dot = 1 unit, dash = 3, intra-character gap = 1, character gap = 3,
/// and word gap = 7. The production flashlight tool uses a 0.2-second unit.
public enum MorseCode {
    public static let unitSeconds = 0.2
    public struct Transmission: Sendable, Equatable, Codable {
        public let sourceText: String
        public let normalizedText: String
        public let notation: String
        public let pulses: [MorsePulse]

        public var totalUnits: Int { pulses.reduce(0) { $0 + $1.units } }
        public var durationSeconds: Double { Double(totalUnits) * MorseCode.unitSeconds }
    }

    public enum EncodingError: Error, Sendable, Equatable, CustomStringConvertible {
        case empty
        case unsupportedCharacters(String)

        public var description: String {
            switch self {
            case .empty:
                return "Morse text must not be empty."
            case .unsupportedCharacters(let characters):
                return "Morse text contains unsupported characters: \(characters)."
            }
        }
    }

    public static func encode(_ source: String) throws -> Transmission {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EncodingError.empty }
        let folded = trimmed.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ).uppercased()
        let words = folded.split(whereSeparator: { $0.isWhitespace })
        var unsupported = Set<Character>()
        for character in words.joined() where alphabet[character] == nil {
            unsupported.insert(character)
        }
        guard unsupported.isEmpty else {
            throw EncodingError.unsupportedCharacters(String(unsupported.sorted()))
        }

        var pulses: [MorsePulse] = []
        var notationWords: [String] = []
        for (wordIndex, word) in words.enumerated() {
            var notationLetters: [String] = []
            for (letterIndex, character) in word.enumerated() {
                let pattern = alphabet[character]!
                notationLetters.append(pattern)
                for (symbolIndex, symbol) in pattern.enumerated() {
                    pulses.append(MorsePulse(isOn: true, units: symbol == "." ? 1 : 3))
                    if symbolIndex < pattern.count - 1 {
                        pulses.append(MorsePulse(isOn: false, units: 1))
                    }
                }
                if letterIndex < word.count - 1 {
                    pulses.append(MorsePulse(isOn: false, units: 3))
                }
            }
            notationWords.append(notationLetters.joined(separator: " "))
            if wordIndex < words.count - 1 {
                pulses.append(MorsePulse(isOn: false, units: 7))
            }
        }

        let transmission = Transmission(
            sourceText: source,
            normalizedText: words.map(String.init).joined(separator: " "),
            notation: notationWords.joined(separator: " / "),
            pulses: pulses
        )
        return transmission
    }

    // ITU letters, digits, and the punctuation people commonly dictate to an assistant.
    private static let alphabet: [Character: String] = [
        "A": ".-", "B": "-...", "C": "-.-.", "D": "-..", "E": ".",
        "F": "..-.", "G": "--.", "H": "....", "I": "..", "J": ".---",
        "K": "-.-", "L": ".-..", "M": "--", "N": "-.", "O": "---",
        "P": ".--.", "Q": "--.-", "R": ".-.", "S": "...", "T": "-",
        "U": "..-", "V": "...-", "W": ".--", "X": "-..-", "Y": "-.--",
        "Z": "--..",
        "0": "-----", "1": ".----", "2": "..---", "3": "...--", "4": "....-",
        "5": ".....", "6": "-....", "7": "--...", "8": "---..", "9": "----.",
        ".": ".-.-.-", ",": "--..--", "?": "..--..", "'": ".----.",
        "!": "-.-.--", "/": "-..-.", "(": "-.--.", ")": "-.--.-",
        "&": ".-...", ":": "---...", ";": "-.-.-.", "=": "-...-",
        "+": ".-.-.", "-": "-....-", "_": "..--.-", "\"": ".-..-.",
        "$": "...-..-", "@": ".--.-.",
    ]
}
