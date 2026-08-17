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
        VStack(alignment: .leading, spacing: 16) {
            Label(spec.description, systemImage: "hand.raised")
                .font(.headline)

            GroupBox("Details") {
                ForEach(call.arguments.keys.sorted(), id: \.self) { key in
                    LabeledContent(key, value: displayValue(call.arguments[key]))
                }
            }

            HStack {
                Button("Cancel", role: .cancel) { finish(false) }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.bordered)
                Button("Do it") { finish(true) }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
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
