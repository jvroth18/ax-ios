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

    func testRejectsEmptyUnsupportedOverlongAndOverDurationInputs() {
        XCTAssertThrowsError(try MorseCode.encode("   ")) { error in
            XCTAssertEqual(error as? MorseCode.EncodingError, .empty)
        }
        XCTAssertThrowsError(try MorseCode.encode("SOS 🚀")) { error in
            XCTAssertEqual(error as? MorseCode.EncodingError, .unsupportedCharacters("🚀"))
        }
        XCTAssertThrowsError(try MorseCode.encode(String(repeating: "E", count: 65))) { error in
            XCTAssertEqual(error as? MorseCode.EncodingError, .tooLong(65))
        }
        XCTAssertThrowsError(try MorseCode.encode(String(repeating: "0", count: 64))) { error in
            guard case .durationExceeded(let seconds) = error as? MorseCode.EncodingError else {
                return XCTFail("expected durationExceeded, got \(error)")
            }
            XCTAssertGreaterThan(seconds, MorseCode.maxDurationSeconds)
        }
    }
}
