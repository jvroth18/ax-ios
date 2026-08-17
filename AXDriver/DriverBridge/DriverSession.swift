#if AX_DRIVER
import Foundation
import UIKit
import Observation

/// The observe → decide → act loop for full-UI automation. Hard-capped step count,
/// user-visible step log, and a stop button (see docs — this whole module is experimental).
@Observable @MainActor
final class DriverSession {

    enum State: Equatable {
        case connecting
        case running(step: Int, log: [String])
        case finished(String)
        case failed(String)
    }

    private(set) var state: State = .connecting
    private var cancelled = false

    static let maxSteps = 15

    func run(goal: String, planner: VLMPlanner) async {
        var wda = WDAClient()
        guard await wda.isRunning() else {
            state = .failed("WebDriverAgent is not running on this device. See AXDriver/WDA-SETUP.md.")
            return
        }
        do {
            try await wda.createSession()
            var log: [String] = []
            let screen = UIScreen.main.bounds.size

            for step in 1...Self.maxSteps {
                guard !cancelled else { return }
                state = .running(step: step, log: log)

                let screenshot = try await wda.screenshot()
                let action = try await planner.nextAction(goal: goal, stepsSoFar: log, screenshot: screenshot)

                switch action {
                case .tap(let xf, let yf, let why):
                    try await wda.tap(x: xf * screen.width, y: yf * screen.height)
                    log.append("tapped (\(String(format: "%.2f", xf)), \(String(format: "%.2f", yf))): \(why)")
                case .type(let text):
                    try await wda.typeText(text)
                    log.append("typed \"\(text)\"")
                case .launch(let bundleID):
                    try await wda.launchApp(bundleID: bundleID)
                    log.append("launched \(bundleID)")
                case .home:
                    try await wda.pressHome()
                    log.append("pressed home")
                case .done(let summary):
                    state = .finished(summary)
                    return
                case .stuck(let reason):
                    state = .failed("Model is stuck: \(reason)")
                    return
                }
                // Let animations settle before the next screenshot
                try await Task.sleep(for: .milliseconds(800))
            }
            state = .failed("Step limit (\(Self.maxSteps)) reached without finishing.")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stop() { cancelled = true }
}
#endif
