import SwiftUI

/// The 90s design system: a Windows-95-era desktop app. Silver chrome with 3D bevels,
/// navy title bars, block progress bars, checkboxes, status bars, and green-on-black
/// system-monitor charts. Every screen is a "window" so the app reads as one machine.
enum W95 {
    // Chrome
    static let face = Color(red: 0.76, green: 0.76, blue: 0.76)
    static let faceLight = Color(red: 0.87, green: 0.87, blue: 0.87)
    static let white = Color.white
    static let shadow = Color(red: 0.50, green: 0.50, blue: 0.50)
    static let dark = Color(red: 0.25, green: 0.25, blue: 0.25)
    static let text = Color.black

    // Title bar
    static let titleA = Color(red: 0.0, green: 0.0, blue: 0.50)
    static let titleB = Color(red: 0.06, green: 0.52, blue: 0.82)

    // Desktop + web accents
    static let desktop = Color(red: 0.0, green: 0.50, blue: 0.50)
    static let link = Color(red: 0.0, green: 0.0, blue: 0.93)
    static let maroon = Color(red: 0.50, green: 0.0, blue: 0.0)
    static let navy = titleA

    // System-monitor charts
    static let monBackground = Color.black
    static let monTrace = Color(red: 0.0, green: 1.0, blue: 0.25)
    static let monGrid = Color(red: 0.0, green: 0.45, blue: 0.12)

    static func ui(_ size: CGFloat = 13, bold: Bool = false) -> Font {
        .system(size: size, weight: bold ? .bold : .regular)
    }
    static func mono(_ size: CGFloat = 12, bold: Bool = false) -> Font {
        .system(size: size, weight: bold ? .bold : .regular, design: .monospaced)
    }
}

/// Classic two-pixel 3D bevel. Raised = light top-left / dark bottom-right;
/// sunken inverts it (text wells, list boxes, the desktop's inset panels).
struct W95BevelOverlay: View {
    var sunken = false

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let tl1: Color = sunken ? W95.shadow : W95.faceLight
            let tl2: Color = sunken ? W95.dark : W95.white
            let br1: Color = sunken ? W95.white : W95.dark
            let br2: Color = sunken ? W95.faceLight : W95.shadow

            func line(_ from: CGPoint, _ to: CGPoint, _ color: Color) {
                var path = Path()
                path.move(to: from)
                path.addLine(to: to)
                context.stroke(path, with: .color(color), lineWidth: 1)
            }
            // Outer frame
            line(.init(x: 0.5, y: h), .init(x: 0.5, y: 0.5), tl1)
            line(.init(x: 0.5, y: 0.5), .init(x: w, y: 0.5), tl1)
            line(.init(x: w - 0.5, y: 0.5), .init(x: w - 0.5, y: h - 0.5), br1)
            line(.init(x: 0, y: h - 0.5), .init(x: w, y: h - 0.5), br1)
            // Inner frame
            line(.init(x: 1.5, y: h - 1), .init(x: 1.5, y: 1.5), tl2)
            line(.init(x: 1.5, y: 1.5), .init(x: w - 1, y: 1.5), tl2)
            line(.init(x: w - 1.5, y: 1.5), .init(x: w - 1.5, y: h - 1.5), br2)
            line(.init(x: 1, y: h - 1.5), .init(x: w - 1, y: h - 1.5), br2)
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// Raised chrome panel (buttons, toolbars, window faces).
    func w95Raised() -> some View {
        background(W95.face).overlay(W95BevelOverlay())
    }
    /// Sunken well with a white page inside (text fields, lists, content areas).
    func w95Well(background: Color = .white) -> some View {
        self.background(background).overlay(W95BevelOverlay(sunken: true))
    }
}

/// Navy gradient title bar with decorative window controls.
struct W95TitleBar: View {
    let title: String
    var onClose: (() -> Void)?
    var onMinimize: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(W95.ui(13, bold: true))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
            if let onMinimize {
                Button(action: onMinimize) { controlBox("─") }
                    .buttonStyle(.plain)
            } else {
                controlBox("─")
            }
            if let onClose {
                Button(action: onClose) { controlBox("✕") }
                    .buttonStyle(.plain)
            } else {
                controlBox("✕")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(LinearGradient(colors: [W95.titleA, W95.titleB], startPoint: .leading, endPoint: .trailing))
    }

    private func controlBox(_ glyph: String) -> some View {
        Text(glyph)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(W95.text)
            .frame(width: 20, height: 17)
            .w95Raised()
    }
}

/// A full "window": title bar, chrome frame, your content inside. The standard
/// screen container — pushed screens pass `onClose` wired to dismiss.
struct W95Window<Content: View>: View {
    let title: String
    var onClose: (() -> Void)?
    var onMinimize: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            W95TitleBar(title: title, onClose: onClose, onMinimize: onMinimize)
            content
        }
        .padding(3)
        .w95Raised()
    }
}

/// A desktop icon: pixel-era pictogram on a raised tile, white label below.
struct W95DesktopIcon: View {
    let glyph: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Text(glyph)
                    .font(.system(size: 26))
                    .frame(width: 52, height: 52)
                    .background(W95.face)
                    .overlay(W95BevelOverlay())
                Text(label)
                    .font(W95.ui(11))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.8), radius: 0, x: 1, y: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Gray beveled push button; the bevel inverts while pressed, like the real thing.
struct W95ButtonStyle: ButtonStyle {
    var bold = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(W95.ui(13, bold: bold))
            .foregroundStyle(W95.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(W95.face)
            .overlay(W95BevelOverlay(sunken: configuration.isPressed))
            .offset(x: configuration.isPressed ? 1 : 0, y: configuration.isPressed ? 1 : 0)
    }
}

/// Etched group box with a label breaking the top edge.
struct W95GroupBox<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .padding(.top, 6)
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(W95.shadow, lineWidth: 1)
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(W95.white, lineWidth: 1).offset(x: 1, y: 1))
        )
        .overlay(alignment: .topLeading) {
            Text(label)
                .font(W95.ui(12))
                .foregroundStyle(W95.text)
                .padding(.horizontal, 4)
                .background(W95.face)
                .offset(x: 8, y: -8)
        }
        .padding(.top, 8)
    }
}

/// Sunken status bar strip along a window's bottom edge.
struct W95StatusBar: View {
    let fields: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(fields.indices, id: \.self) { index in
                Text(fields[index])
                    .font(W95.ui(11))
                    .foregroundStyle(W95.text)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .frame(maxWidth: index == 0 ? .infinity : nil, alignment: .leading)
                    .w95Well(background: W95.face)
            }
        }
        .padding(2)
        .background(W95.face)
    }
}

/// The iconic block progress bar: discrete navy chunks marching across a sunken well.
struct W95ProgressBar: View {
    /// 0...1
    var value: Double
    var blocks: Int = 20

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<blocks, id: \.self) { index in
                Rectangle()
                    .fill(Double(index) / Double(blocks) < value ? W95.navy : .clear)
                    .frame(height: 14)
            }
        }
        .padding(3)
        .w95Well(background: .white)
    }
}

/// Square checkbox toggle (☑), for Settings.
struct W95CheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8) {
                ZStack {
                    Rectangle().fill(.white).frame(width: 15, height: 15)
                        .overlay(W95BevelOverlay(sunken: true))
                    if configuration.isOn {
                        Text("✓").font(.system(size: 11, weight: .bold)).foregroundStyle(W95.text)
                    }
                }
                configuration.label
                    .font(W95.ui(13))
                    .foregroundStyle(W95.text)
            }
        }
        .buttonStyle(.plain)
    }
}

/// The `<blink>` tag lives again. Use sparingly — that's what makes it funny.
struct W95Blink: ViewModifier {
    @State private var visible = true

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0.15)
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(600))
                    visible.toggle()
                }
            }
    }
}

extension View {
    func w95Blink() -> some View { modifier(W95Blink()) }
}

/// Teal desktop behind every window.
struct W95Desktop: View {
    var body: some View {
        W95.desktop.ignoresSafeArea()
    }
}

/// Hourglass wait indicator (the 90s spinner).
struct W95Hourglass: View {
    @State private var flipped = false

    var body: some View {
        Text("⌛")
            .font(.system(size: 14))
            .rotationEffect(.degrees(flipped ? 180 : 0))
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(700))
                    withAnimation(.easeInOut(duration: 0.3)) { flipped.toggle() }
                }
            }
    }
}
