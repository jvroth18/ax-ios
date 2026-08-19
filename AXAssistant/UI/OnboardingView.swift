import SwiftUI
import Speech
import AVFoundation

/// First-launch flow, styled as a classic setup wizard: navy sidebar, numbered steps,
/// Back / Next buttons. Privacy stance → permissions → Action Button assignment.
struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var page = 0

    private let titles = ["Welcome", "Microphone & Speech", "Action Button"]

    var body: some View {
        ZStack {
            W95Desktop()
            W95Window(title: "AX Setup Wizard") {
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 0) {
                        sidebar
                        pageContent
                            .padding(14)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .background(W95.face)
                    }
                    Divider().background(W95.shadow)
                    buttonRow
                }
            }
            .padding(10)
        }
        .interactiveDismissDisabled()
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AX")
                .font(.system(size: 30, weight: .black))
                .foregroundStyle(.white)
            Text("SETUP")
                .font(W95.mono(11, bold: true))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            ForEach(titles.indices, id: \.self) { index in
                Text("\(index + 1). \(titles[index])")
                    .font(W95.ui(11, bold: index == page))
                    .foregroundStyle(index == page ? .white : .white.opacity(0.55))
            }
            Spacer()
        }
        .padding(10)
        .frame(width: 120)
        .frame(maxHeight: .infinity)
        .background(LinearGradient(colors: [W95.titleA, W95.titleB], startPoint: .top, endPoint: .bottom))
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case 0:
            wizardPage(
                title: "Everything stays on this iPhone",
                lines: [
                    "AX runs a language model locally. Your voice, your requests, and the model's replies never touch a server.",
                    "The only download is the model itself (about 1 GB, one time).",
                ]
            )
        case 1:
            wizardPage(
                title: "Microphone & speech",
                lines: [
                    "AX needs the mic to hear you and on-device speech recognition to transcribe you.",
                    "iOS will ask for both — everything is processed locally.",
                ]
            )
        default:
            wizardPage(
                title: "Assign your Action Button",
                lines: [
                    "1. Open Settings → Action Button",
                    "2. Swipe to \u{201C}Shortcut\u{201D}",
                    "3. Choose \u{201C}Ask AX\u{201D}",
                    "Then press and hold the Action Button any time to talk to AX.",
                ]
            )
        }
    }

    private func wizardPage(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(W95.ui(16, bold: true))
                .foregroundStyle(W95.text)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(W95.ui(13))
                    .foregroundStyle(W95.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var buttonRow: some View {
        HStack(spacing: 6) {
            Spacer()
            Button("< Back") { page = max(0, page - 1) }
                .buttonStyle(W95ButtonStyle())
                .disabled(page == 0)
            switch page {
            case 0:
                Button("Next >") { page = 1 }.buttonStyle(W95ButtonStyle(bold: true))
            case 1:
                Button("Allow Access") { requestPermissions() }.buttonStyle(W95ButtonStyle(bold: true))
            default:
                Button("Finish") { isPresented = false }.buttonStyle(W95ButtonStyle(bold: true))
            }
        }
        .padding(8)
        .background(W95.face)
    }

    private func requestPermissions() {
        Task {
            await AVAudioApplication.requestRecordPermission()
            try? await Transcriber.ensureAssetsInstalled()
            page = 2
        }
    }
}
