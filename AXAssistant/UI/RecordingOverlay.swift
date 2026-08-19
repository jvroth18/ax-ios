import SwiftUI

/// Recording strip: blinking red dot, plain words, a Stop button. Very 1996.
struct RecordingOverlay: View {
    let session: VoiceSession?

    var body: some View {
        HStack(spacing: 8) {
            Text("●")
                .foregroundStyle(.red)
                .font(.system(size: 13))
                .w95Blink()
            Text("Recording — pause to send")
                .font(W95.ui(12))
                .foregroundStyle(W95.text)
            Spacer()
            Button("Stop") { session?.cancel() }
                .buttonStyle(W95ButtonStyle())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .w95Well(background: W95.faceLight)
    }
}
