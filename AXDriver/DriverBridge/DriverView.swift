#if AX_DRIVER
import SwiftUI

/// The experimental full-UI-automation screen. Requires the WebDriverAgent runner to be
/// running on this device (see AXDriver/WDA-SETUP.md).
struct DriverView: View {
    let modelManager: ModelManager

    @State private var goal = ""
    @State private var planner: VLMPlanner?
    @State private var session = DriverSession()
    @State private var loadingModel = false
    @State private var status = ""

    var body: some View {
        Form {
            Section {
                Text("Experimental. The vision model reads screenshots and taps for you. Every step is logged; use Stop any time.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Goal") {
                TextField("e.g. Open Settings and enable Airplane Mode", text: $goal, axis: .vertical)
                Button(runButtonTitle) { Task { await run() } }
                    .disabled(goal.isEmpty || loadingModel || isRunning)
                if isRunning {
                    Button("Stop", role: .destructive) { session.stop() }
                }
            }

            Section("Status") {
                if loadingModel {
                    ProgressView(status)
                } else {
                    statusView
                }
            }
        }
        .navigationTitle("Driver")
    }

    private var isRunning: Bool {
        if case .running = session.state { return true }
        if case .connecting = session.state { return goalStarted }
        return false
    }

    @State private var goalStarted = false

    private var runButtonTitle: String {
        planner == nil ? "Load vision model & run" : "Run"
    }

    @ViewBuilder
    private var statusView: some View {
        switch session.state {
        case .connecting:
            Text(goalStarted ? "Connecting to WebDriverAgent…" : "Idle")
                .foregroundStyle(.secondary)
        case .running(let step, let log):
            VStack(alignment: .leading, spacing: 4) {
                Text("Step \(step)/\(DriverSession.maxSteps)").font(.headline)
                ForEach(log.indices, id: \.self) { index in
                    Text(log[index]).font(.caption).foregroundStyle(.secondary)
                }
            }
        case .finished(let summary):
            Label(summary, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
        }
    }

    private func run() async {
        goalStarted = true
        if planner == nil {
            loadingModel = true
            status = "Unloading text model…"
            modelManager.unload()  // single-resident-model rule on 8 GB devices
            status = "Loading \(VLMPlanner.modelID)…"
            do {
                planner = try await VLMPlanner.load()
            } catch {
                loadingModel = false
                session = DriverSession()
                goalStarted = false
                status = "VLM load failed: \(error.localizedDescription)"
                return
            }
            loadingModel = false
        }
        guard let planner else { return }
        session = DriverSession()
        await session.run(goal: goal, planner: planner)
        goalStarted = false
    }
}
#endif
