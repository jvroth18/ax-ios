import SwiftUI

/// Shown in the main window when the selected model isn't loaded: a file-copy-dialog
/// style download flow with the block progress bar.
struct ModelDownloadView: View {
    let modelManager: ModelManager
    /// Opens the Model Library window (windowed shell; no navigation pushes).
    var onOpenLibrary: () -> Void = {}

    var body: some View {
        VStack(spacing: 14) {
            Spacer()

            switch modelManager.state {
            case .idle:
                W95GroupBox(label: "Welcome") {
                    Text("AX runs \(modelManager.choice.name) entirely on this iPhone. Nothing you say ever leaves the device.")
                        .font(W95.ui(13))
                    Text("One-time download: \(modelManager.choice.sizeLabel). Wi-Fi recommended.")
                        .font(W95.ui(11))
                        .foregroundStyle(W95.shadow)
                }
                Button("Download Now") { Task { await modelManager.downloadAndLoad() } }
                    .buttonStyle(W95ButtonStyle(bold: true))
                HStack(spacing: 4) {
                    Text("Or pick a different model in the")
                        .font(W95.ui(12))
                        .foregroundStyle(W95.shadow)
                    Button(action: onOpenLibrary) {
                        Text("Model Library")
                            .font(W95.ui(12))
                            .foregroundStyle(W95.link)
                            .underline()
                    }
                    .buttonStyle(.plain)
                }

            case .downloading(let progress):
                W95GroupBox(label: "Downloading") {
                    Text("Copying '\(modelManager.choice.name)'…")
                        .font(W95.ui(13))
                    W95ProgressBar(value: progress)
                    Text(downloadDetail(progress))
                        .font(W95.mono(11))
                        .foregroundStyle(W95.text)
                    Text("Keep the app open. A healthy download moves within seconds.")
                        .font(W95.ui(11))
                        .foregroundStyle(W95.shadow)
                }
                Button("Cancel") { modelManager.cancelDownload() }
                    .buttonStyle(W95ButtonStyle())

            case .loading:
                HStack(spacing: 8) {
                    W95Hourglass()
                    Text("Loading model into memory…")
                        .font(W95.ui(13))
                }

            case .ready:
                EmptyView()

            case .failed(let message):
                W95GroupBox(label: "Error") {
                    Text("✗ \(message)")
                        .font(W95.ui(12, bold: true))
                        .foregroundStyle(.red)
                }
                Button("Retry") { Task { await modelManager.downloadAndLoad() } }
                    .buttonStyle(W95ButtonStyle(bold: true))
            }

            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(W95.face)
    }

    private func downloadDetail(_ progress: Double) -> String {
        let totalMB = modelManager.choice.downloadGB * 1000
        return String(format: "%.0f MB of %.0f MB (%d%%)", progress * totalMB, totalMB, Int(progress * 100))
    }
}
