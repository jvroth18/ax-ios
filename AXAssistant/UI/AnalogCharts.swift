import SwiftUI

/// Analog needle gauge in hardware-monitor style: white dial card, black ticks,
/// red zone, red needle.
struct AXNeedleGauge: View {
    var value: Double
    var maxValue: Double
    var label: String
    var unit: String
    /// Fraction of the scale where the red zone begins (0...1).
    var redline: Double = 0.85

    /// Needle sweep in degrees, centered on straight up.
    private let sweep: Double = 120

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                dialFace
                needle
                Circle()
                    .fill(W95.dark)
                    .frame(width: 9, height: 9)
                    .offset(y: 26)
            }
            .frame(height: 90)
            .clipped()
            Text(String(format: value >= 100 ? "%.0f %@" : "%.1f %@", value, unit))
                .font(W95.mono(12, bold: true))
                .foregroundStyle(W95.text)
            Text(label)
                .font(W95.ui(11))
                .foregroundStyle(W95.shadow)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .w95Well(background: .white)
    }

    private var fraction: Double {
        maxValue > 0 ? min(max(value / maxValue, 0), 1) : 0
    }

    private var dialFace: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height - 10)
            let radius = min(size.width / 2 - 8, size.height - 20)
            let start = Angle.degrees(-90 - sweep / 2)

            var redArc = Path()
            redArc.addArc(
                center: center,
                radius: radius,
                startAngle: start + .degrees(sweep * redline),
                endAngle: start + .degrees(sweep),
                clockwise: false
            )
            context.stroke(redArc, with: .color(W95.maroon), lineWidth: 4)

            for tick in 0...10 {
                let angle = start + .degrees(sweep * Double(tick) / 10)
                let long = tick % 2 == 0
                let outer = point(center: center, radius: radius, angle: angle)
                let inner = point(center: center, radius: radius - (long ? 10 : 6), angle: angle)
                var path = Path()
                path.move(to: inner)
                path.addLine(to: outer)
                context.stroke(path, with: .color(W95.text), lineWidth: long ? 1.5 : 1)
                if long {
                    let labelPoint = point(center: center, radius: radius - 19, angle: angle)
                    context.draw(
                        Text(String(format: "%.0f", maxValue * Double(tick) / 10))
                            .font(.system(size: 7, weight: .semibold, design: .monospaced))
                            .foregroundStyle(W95.text),
                        at: labelPoint
                    )
                }
            }
        }
    }

    private var needle: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height - 10)
            let length = min(geo.size.width / 2 - 8, geo.size.height - 20) - 4
            Capsule()
                .fill(Color.red)
                .frame(width: 2.5, height: length)
                .rotationEffect(.degrees(-sweep / 2 + sweep * fraction), anchor: .bottom)
                .position(x: center.x, y: center.y - length / 2)
                .animation(.spring(response: 0.6, dampingFraction: 0.55), value: fraction)
        }
    }

    private func point(center: CGPoint, radius: CGFloat, angle: Angle) -> CGPoint {
        CGPoint(
            x: center.x + radius * cos(angle.radians),
            y: center.y + radius * sin(angle.radians)
        )
    }
}

/// Task-Manager-style history chart: bright green trace scrolling across a black
/// gridded field, newest sample at the right edge.
struct AXStripChart: View {
    var values: [Double]
    var maxValue: Double
    var label: String
    var trailing: String = ""
    var color: Color = W95.monTrace
    /// Number of samples the field width represents.
    var window: Int = 60

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Canvas { context, size in
                let minor: CGFloat = 12
                var grid = Path()
                var x: CGFloat = size.width
                while x > 0 { grid.move(to: .init(x: x, y: 0)); grid.addLine(to: .init(x: x, y: size.height)); x -= minor }
                var y: CGFloat = size.height
                while y > 0 { grid.move(to: .init(x: 0, y: y)); grid.addLine(to: .init(x: size.width, y: y)); y -= minor }
                context.stroke(grid, with: .color(W95.monGrid), lineWidth: 0.5)

                let samples = Array(values.suffix(window))
                guard samples.count >= 2, maxValue > 0 else { return }
                let stepX = size.width / CGFloat(window - 1)
                let startX = size.width - stepX * CGFloat(samples.count - 1)

                var trace = Path()
                for (index, sample) in samples.enumerated() {
                    let px = startX + stepX * CGFloat(index)
                    let py = size.height - CGFloat(min(sample / maxValue, 1)) * (size.height - 4) - 2
                    if index == 0 { trace.move(to: .init(x: px, y: py)) }
                    else { trace.addLine(to: .init(x: px, y: py)) }
                }
                context.stroke(trace, with: .color(color), lineWidth: 1.5)
            }
            .frame(height: 80)
            .w95Well(background: W95.monBackground)
            HStack {
                Text(label)
                    .font(W95.ui(11))
                    .foregroundStyle(W95.text)
                Spacer()
                Text(trailing)
                    .font(W95.mono(10))
                    .foregroundStyle(W95.shadow)
            }
        }
    }
}
