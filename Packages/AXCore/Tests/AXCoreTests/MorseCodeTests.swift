import XCTest
@testable import AXCore

final class MorseCodeTests: XCTestCase {
    func testEncodesSOSWithExactStandardTiming() throws {
        let transmission = try MorseCode.encode("SOS")

        XCTAssertEqual(transmission.normalizedText, "SOS")
        XCTAssertEqual(transmission.notation, "... --- ...")
        XCTAssertEqual(transmission.totalUnits, 27)
        XCTAssertEqual(transmission.durationSeconds, 5.4, accuracy: 0.0001)
        XCTAssertEqual(transmission.pulses, [
            .init(isOn: true, units: 1), .init(isOn: false, units: 1),
            .init(isOn: true, units: 1), .init(isOn: false, units: 1),
            .init(isOn: true, units: 1), .init(isOn: false, units: 3),
            .init(isOn: true, units: 3), .init(isOn: false, units: 1),
            .init(isOn: true, units: 3), .init(isOn: false, units: 1),
            .init(isOn: true, units: 3), .init(isOn: false, units: 3),
            .init(isOn: true, units: 1), .init(isOn: false, units: 1),
            .init(isOn: true, units: 1), .init(isOn: false, units: 1),
            .init(isOn: true, units: 1),
        ])
    }

    func testUsesSevenUnitsBetweenWordsWithoutAddingLetterGap() throws {
        let transmission = try MorseCode.encode("E T")
        XCTAssertEqual(transmission.notation, ". / -")
        XCTAssertEqual(transmission.pulses, [
            .init(isOn: true, units: 1),
            .init(isOn: false, units: 7),
            .init(isOn: true, units: 3),
        ])
    }

    func testNormalizesCaseWhitespaceAndDiacritics() throws {
        let transmission = try MorseCode.encode("  héllo   wörld  ")
        XCTAssertEqual(transmission.normalizedText, "HELLO WORLD")
        XCTAssertEqual(transmission.notation, ".... . .-.. .-.. --- / .-- --- .-. .-.. -..")
    }

    func testSupportsDigitsAndCommonPunctuation() throws {
        let transmission = try MorseCode.encode("Meet @ 5!")
        XCTAssertEqual(transmission.normalizedText, "MEET @ 5!")
        XCTAssertTrue(transmission.notation.contains(".--.-."))
        XCTAssertTrue(transmission.notation.hasSuffix("..... -.-.--"))
    }

    func testRejectsEmptyAndUnsupportedInputs() {
        XCTAssertThrowsError(try MorseCode.encode("   ")) { error in
            XCTAssertEqual(error as? MorseCode.EncodingError, .empty)
        }
        XCTAssertThrowsError(try MorseCode.encode("SOS 🚀")) { error in
            XCTAssertEqual(error as? MorseCode.EncodingError, .unsupportedCharacters("🚀"))
        }
    }

    func testAllowsLongComplexSentencesWithoutLengthOrDurationCaps() throws {
        let source = String(repeating: "Meet me at 5, bring maps! ", count: 20)
        let transmission = try MorseCode.encode(source)

        XCTAssertGreaterThan(source.count, 64)
        XCTAssertGreaterThan(transmission.durationSeconds, 120)
        XCTAssertTrue(transmission.normalizedText.hasPrefix("MEET ME AT 5, BRING MAPS!"))
    }
}
