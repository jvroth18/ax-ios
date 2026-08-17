import SwiftUI
import Speech
import AVFoundation

/// First-launch walkthrough: privacy stance → permissions → Action Button assignment.
/// The Action Button page is illustrated text — iOS offers no deep link into that
/// Settings pane, so clear steps are the best any app can do.
struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var page = 0

    var body: some View {
        TabView(selection: $page) {
            onboardingPage(
                symbol: "iphone.and.arrow.forward.inward",
                title: "Everything stays on this iPhone",
                lines: [
                    "AX runs a language model locally. Your voice, your requests, and the model's replies never touch a server.",
                    "The only download is the model itself (~1.1 GB, one time).",
                ],
                button: ("Next", { page = 1 })
            ).tag(0)

            onboardingPage(
                symbol: "mic.badge.plus",
                title: "Microphone & speech",
                lines: [
                    "AX needs the mic to hear you and on-device speech recognition to transcribe you.",
                    "iOS will ask for both — everything is processed locally.",
                ],
                button: ("Allow access", requestPermissions)
            ).tag(1)

            onboardingPage(
                symbol: "button.horizontal.top.press",
                title: "Assign your Action Button",
                lines: [
                    "1. Open Settings → Action Button",
                    "2. Swipe to “Shortcut”",
                    "3. Choose “Ask AX”",
                    "Then press and hold the Action Button any time to talk to AX.",
                ],
                button: ("Done", { isPresented = false })
            ).tag(2)
        }
        .tabViewStyle(.page)
        .interactiveDismissDisabled()
    }

    private func requestPermissions() {
        Task {
            await AVAudioApplication.requestRecordPermission()
            try? await Transcriber.ensureAssetsInstalled()
            page = 2
        }
    }

    @ViewBuilder
    private func onboardingPage(
        symbol: String, title: String, lines: [String], button: (String, () -> Void)
    ) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text(title).font(.title2.bold())
            VStack(alignment: .leading, spacing: 10) {
                ForEach(lines, id: \.self) { line in
                    Text(line).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 32)
            Spacer()
            Button(button.0, action: button.1)
                .buttonStyle(.borderedProminent)
                .padding(.bottom, 48)
        }
    }
}
