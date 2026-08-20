import SwiftUI

/// A compact in-app QWERTY keyboard. It keeps the muscle-memory layout of the
/// iOS keyboard while making text entry feel like part of AX's visual world.
struct W95Keyboard: View {
    @Binding var text: String
    let onReturn: () -> Void
    let onDismiss: () -> Void

    @State private var uppercase = false
    @State private var showsNumbers = false

    private let letterRows = [
        Array("qwertyuiop"),
        Array("asdfghjkl"),
        Array("zxcvbnm")
    ]
    private let numberRows = [
        Array("1234567890"),
        Array("-/:;()$&@\""),
        Array(".,?!'[]")
    ]

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(showsNumbers ? "SYMBOLS" : uppercase ? "CAPS" : "QWERTY")
                    .font(W95.ui(10, bold: true))
                    .foregroundStyle(W95.shadow)
                Spacer()
                Button("Hide") { onDismiss() }
                    .font(W95.ui(11, bold: true))
                    .buttonStyle(.plain)
            }

            ForEach(Array(activeRows.enumerated()), id: \.offset) { row, keys in
                HStack(spacing: 4) {
                    if row == 2 && !showsNumbers {
                        key("⇧", width: 42, selected: uppercase) {
                            uppercase.toggle()
                        }
                    }
                    ForEach(Array(keys.enumerated()), id: \.offset) { _, character in
                        key(label(for: character)) { insert(character) }
                    }
                    if row == 2 {
                        key("⌫", width: 42) { text = String(text.dropLast()) }
                            .accessibilityLabel("Delete")
                    }
                }
            }

            HStack(spacing: 5) {
                key(showsNumbers ? "ABC" : "123", width: 52) { showsNumbers.toggle() }
                key(",", width: 34) { text.append(",") }
                key("space") { text.append(" ") }
                key(".", width: 34) { text.append(".") }
                key("return", width: 70, enabled: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    onReturn()
                }
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 6)
        .background(W95.face)
        .overlay(W95BevelOverlay())
        .animation(.easeOut(duration: 0.15), value: showsNumbers)
    }

    private var activeRows: [[Character]] { showsNumbers ? numberRows : letterRows }

    private func label(for character: Character) -> String {
        uppercase && !showsNumbers ? String(character).uppercased() : String(character)
    }

    private func insert(_ character: Character) {
        text.append(contentsOf: label(for: character))
        if uppercase && !showsNumbers { uppercase = false }
    }

    private func key(
        _ title: String,
        width: CGFloat? = nil,
        selected: Bool = false,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(W95.ui(title.count > 2 ? 11 : 16, bold: title.count > 2))
                .foregroundStyle(enabled ? W95.text : W95.shadow)
                .frame(maxWidth: width == nil ? .infinity : nil)
                .frame(width: width, height: 34)
                .background(selected ? W95.white : W95.face)
                .overlay(W95BevelOverlay())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(title)
    }
}
