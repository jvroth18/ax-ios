import SwiftUI

struct ModelDownloadView: View {
    let modelManager: ModelManager

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "cpu")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            switch modelManager.state {
            case .idle:
                Text("AX runs a language model entirely on this iPhone.\nNothing you say ever leaves the device.")
                    .multilineTextAlignment(.center)
                Text("One-time download: \(modelManager.choice.displayName) (\(modelManager.choice.approximateSize)). Wi-Fi recommended.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Download model") {
                    Task { await modelManager.downloadAndLoad() }
                }
                .buttonStyle(.borderedProminent)

            case .downloading(let progress):
                ProgressView("Downloading \(modelManager.choice.displayName)…", value: progress)
                    .padding(.horizontal, 40)

            case .loading:
                ProgressView("Loading model…")

            case .ready:
                EmptyView()

            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Button("Retry") { Task { await modelManager.downloadAndLoad() } }
            }
        }
        .padding()
    }
}
