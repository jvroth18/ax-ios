import SwiftUI
import AXCore

/// Shown before any `.confirm`-risk tool executes. The resume closure feeds the user's
/// decision back into the suspended agent loop.
struct ConfirmSheet: View {
    let call: ToolCall
    let spec: ToolSpec
    let resume: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            W95Desktop()
            // Message-box style: warning icon, question, OK/Cancel.
            W95Window(title: "Confirm Action") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 10) {
                        Text("⚠️").font(.system(size: 28))
                        Text(spec.description)
                            .font(W95.ui(13, bold: true))
                            .foregroundStyle(W95.text)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(call.arguments.keys.sorted(), id: \.self) { key in
                            HStack(alignment: .top) {
                                Text(key).font(W95.mono(11)).foregroundStyle(W95.shadow)
                                Spacer()
                                Text(displayValue(call.arguments[key]))
                                    .font(W95.ui(12))
                                    .foregroundStyle(W95.text)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }
                    .padding(8)
                    .w95Well(background: .white)
                    HStack(spacing: 8) {
                        Spacer()
                        Button("OK") { finish(true) }.buttonStyle(W95ButtonStyle(bold: true))
                        Button("Cancel") { finish(false) }.buttonStyle(W95ButtonStyle())
                        Spacer()
                    }
                }
                .padding(12)
                .background(W95.face)
            }
            .padding(14)
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled()
    }

    private func finish(_ approved: Bool) {
        resume(approved)
        dismiss()
    }

    private func displayValue(_ value: JSONValue?) -> String {
        switch value {
        case .string(let string): return string
        case .number(let number): return number.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(number)) : String(number)
        case .bool(let bool): return bool ? "yes" : "no"
        default: return "—"
        }
    }
}
