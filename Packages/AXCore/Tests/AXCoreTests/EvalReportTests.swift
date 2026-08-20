import XCTest
@testable import AXCore

final class EvalReportTests: XCTestCase {

    private func report(catalogDrift: [String] = []) -> EvalReport {
        let results = EvalSuite.all.prefix(6).enumerated().map { index, evalCase in
            EvalCaseResult(
                evalCase: evalCase,
                judgment: EvalJudgment(
                    outcome: index.isMultiple(of: 3) ? .wrongTool(expected: "a", got: "b") : .pass,
                    emittedCalls: ["toggle_flashlight(state=on)"],
                    executionCovered: index != 1
                ),
                durationSeconds: 1.25
            )
        }
        return EvalReport(
            modelID: "mlx-community/Qwen3-1.7B-4bit",
            catalogDrift: catalogDrift,
            results: Array(results),
            metrics: EvalRunMetrics(
                tokensPerSecond: 23.4, peakFootprintMB: 1780, gpuPeakMB: 1420
            ),
            generatedAt: Date(timeIntervalSince1970: 1_787_000_000)
        )
    }

    func testJSONRoundTripsAndIsStable() throws {
        let original = report()
        let data = try original.jsonData()
        let decoded = try EvalReport.decode(data)
        XCTAssertEqual(decoded.modelID, original.modelID)
        XCTAssertEqual(decoded.passed, original.passed)
        XCTAssertEqual(decoded.results.map(\.id), original.results.map(\.id))
        XCTAssertEqual(decoded.referenceNow, "Wednesday 2026-08-19 14:30, America/New_York")
        // Byte-stable so a committed results file diffs cleanly.
        XCTAssertEqual(try decoded.jsonData(), data)
    }

    func testMarkdownCarriesPerClassScoresAndMetrics() {
        let markdown = report().markdown()
        XCTAssertTrue(markdown.contains("| Class | Pass | Total | Rate |"))
        XCTAssertTrue(markdown.contains("Reference \"now\" pinned to"))
        XCTAssertTrue(markdown.contains("23.4 tok/s"))
        XCTAssertTrue(markdown.contains("1780 MB"))
        XCTAssertTrue(markdown.contains("## Failures"))
        XCTAssertTrue(markdown.contains("pass (unvalidated)"), "uncovered passes must be visible")
    }

    func testCatalogDriftIsShoutedAboutInTheReport() {
        let markdown = report(catalogDrift: ["\"set_timer\" parameter schema differs"]).markdown()
        XCTAssertTrue(markdown.contains("Catalog drift — results are suspect"))
        XCTAssertTrue(markdown.contains("set_timer"))
    }

    func testUncoveredPassesAreCounted() {
        XCTAssertEqual(report().uncoveredPasses, 1)
    }

    func testSuiteManifestRendersEveryCase() throws {
        let markdown = EvalReport.suiteManifestMarkdown()
        for evalCase in EvalSuite.all {
            XCTAssertTrue(markdown.contains("`\(evalCase.id)`"), "missing \(evalCase.id)")
        }
        let json = try EvalReport.suiteManifestJSON()
        XCTAssertGreaterThan(json.count, 1000)
    }

    func testCatalogMirrorsTheLiveRegistryShape() {
        // Self-check of the drift detector: comparing the catalog to itself is clean, and
        // a removed tool is reported.
        XCTAssertTrue(EvalToolCatalog.drift(from: EvalToolCatalog.specs).isEmpty)
        let missing = EvalToolCatalog.drift(from: Array(EvalToolCatalog.specs.dropFirst()))
        XCTAssertEqual(missing, ["eval catalog has \"create_reminder\", live registry does not"])
    }

    func testEveryToolInTheCatalogHasAnExecutionContract() {
        for spec in EvalToolCatalog.specs {
            XCTAssertTrue(
                ContractValidator.axAssistant.covers(tool: spec.name),
                "\(spec.name) has no dry-run contract, so cases using it are scored blind"
            )
        }
    }
}
