import SwiftUI
import UIKit

/// A compact in-app QWERTY keyboard. It keeps the muscle-memory layout of the
/// iOS keyboard while making text entry feel like part of Morse's visual world.
struct W95Keyboard: View {
    @Binding var text: String
    let onDismiss: () -> Void

    @State private var uppercase = false
    @State private var showsNumbers = false
    @State private var hapticTrigger = 0

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
        VStack(spacing: 4) {
            HStack {
                Text(showsNumbers ? "SYMBOLS" : uppercase ? "SHIFT" : "QWERTY")
                    .font(W95.ui(10, bold: true))
                    .foregroundStyle(W95.shadow)
                Spacer()
                Button("Paste") {
                    if let pasted = UIPasteboard.general.string, !pasted.isEmpty {
                        text.append(pasted)
                        hapticTrigger += 1
                    }
                }
                    .font(W95.ui(11, bold: true))
                    .buttonStyle(.plain)
                    .accessibilityHint("Appends text from the clipboard")
                Button("Hide") {
                    hapticTrigger += 1
                    onDismiss()
                }
                    .font(W95.ui(11, bold: true))
                    .buttonStyle(.plain)
                    .accessibilityLabel("Hide keyboard")
            }

            ForEach(Array(activeRows.enumerated()), id: \.offset) { row, keys in
                HStack(spacing: 4) {
                    if row == 1 && !showsNumbers {
                        Spacer().frame(width: 14)
                    }
                    if row == 2 && !showsNumbers {
                        key(
                            "⇧",
                            width: 44,
                            selected: uppercase,
                            accessibilityLabel: "Shift",
                            selectionState: uppercase
                        ) {
                            uppercase.toggle()
                        }
                    }
                    ForEach(Array(keys.enumerated()), id: \.offset) { _, character in
                        key(label(for: character)) { insert(character) }
                    }
                    if row == 2 {
                        key(
                            "⌫",
                            width: 44,
                            enabled: !text.isEmpty,
                            accessibilityLabel: "Delete"
                        ) { text = String(text.dropLast()) }
                    }
                    if row == 1 && !showsNumbers {
                        Spacer().frame(width: 14)
                    }
                }
            }

            HStack(spacing: 5) {
                key(
                    showsNumbers ? "ABC" : "123",
                    width: 54,
                    accessibilityLabel: showsNumbers ? "Letters" : "Numbers"
                ) { showsNumbers.toggle() }
                key(",", width: 44, accessibilityLabel: "Comma") { text.append(",") }
                key("space", accessibilityLabel: "Space") { text.append(" ") }
                key(".", width: 44, accessibilityLabel: "Period") { text.append(".") }
                key(
                    "return",
                    width: 72,
                    enabled: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    accessibilityLabel: "Return"
                ) {
                    text.append("\n")
                }
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 6)
        .background(W95.face)
        .overlay(W95BevelOverlay())
        .animation(.easeOut(duration: 0.15), value: showsNumbers)
        .sensoryFeedback(.impact(weight: .light), trigger: hapticTrigger)
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
        accessibilityLabel: String? = nil,
        selectionState: Bool? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            hapticTrigger += 1
        } label: {
            Text(title)
                .font(W95.ui(title.count > 2 ? 11 : 16, bold: title.count > 2))
                .foregroundStyle(enabled ? W95.text : W95.shadow)
                .frame(maxWidth: width == nil ? .infinity : nil)
                .frame(width: width, height: 44)
                .background(selected ? W95.white : W95.face)
        }
        .buttonStyle(W95KeyboardKeyStyle(selected: selected))
        .disabled(!enabled)
        .accessibilityLabel(accessibilityLabel ?? title)
        .accessibilityValue(selectionState.map { $0 ? "On" : "Off" } ?? "")
    }
}

/// Compact enough for the in-app layout, but with the same physical target and pressed
/// travel as a native key. The inverted bevel is the app's Windows 95 equivalent of an
/// iOS key popover.
private struct W95KeyboardKeyStyle: ButtonStyle {
    let selected: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(selected ? W95.white : W95.face)
            .overlay(W95BevelOverlay(sunken: configuration.isPressed && isEnabled))
            .offset(
                x: configuration.isPressed && isEnabled ? 1 : 0,
                y: configuration.isPressed && isEnabled ? 1 : 0
            )
    }
}
