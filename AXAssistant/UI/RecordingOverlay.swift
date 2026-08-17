import SwiftUI

/// Pulsing waveform bar shown while the mic is live.
struct RecordingOverlay: View {
    let session: VoiceSession?
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .symbolEffect(.variableColor.iterative, isActive: true)
                .font(.title2)
                .foregroundStyle(.red)
            Text("Listening… pause to send")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Stop") { session?.cancel() }
                .buttonStyle(.bordered)
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}
