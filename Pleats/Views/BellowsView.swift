import SwiftUI

/// The pleated bellows drawn across the fold. Pleats run parallel to the fold; the strip widens and the pleats open
/// as the hinge opens, catch light while air flows, and lean with the direction of the stroke.
struct BellowsView: View {
    var extension01: Double
    var pressure: Double
    var direction: BellowsDirection
    var vertical: Bool          // strip runs top-to-bottom
    var theme: Theme

    static let pleats = 9

    var body: some View {
        Canvas { ctx, size in
            let length = vertical ? size.height : size.width
            let thick = vertical ? size.width : size.height
            let n = Self.pleats
            let fold = thick / CGFloat(n)
            // Opening the bellows widens the light faces relative to the dark ones.
            let open = 0.25 + 0.5 * extension01
            let lean = (direction == .pull ? 1.0 : -1.0) * pressure * 0.12

            func rect(_ a: CGFloat, _ w: CGFloat) -> CGRect {
                vertical ? CGRect(x: a, y: 0, width: w, height: length) : CGRect(x: 0, y: a, width: length, height: w)
            }
            func pt(_ along: CGFloat, _ across: CGFloat) -> CGPoint {
                vertical ? CGPoint(x: across, y: along) : CGPoint(x: along, y: across)
            }
            let startP = vertical ? CGPoint(x: 0, y: 0) : CGPoint(x: 0, y: 0)
            let endP = vertical ? CGPoint(x: fold, y: 0) : CGPoint(x: 0, y: fold)
            _ = (startP, endP)

            for i in 0..<n {
                let a = CGFloat(i) * fold
                let lightW = fold * CGFloat(open + lean)
                let darkW = fold - lightW
                // Light face, then the shadowed face of the fold.
                let shine = 0.10 + 0.25 * pressure
                ctx.fill(Path(rect(a, lightW)), with: .linearGradient(
                    Gradient(colors: [theme.bellowsB, theme.bellowsB.opacity(0.85), theme.bellowsA]),
                    startPoint: pt(0, a), endPoint: pt(0, a + lightW)))
                ctx.fill(Path(rect(a, lightW)), with: .color(.white.opacity(shine * 0.35)))
                ctx.fill(Path(rect(a + lightW, darkW)), with: .linearGradient(
                    Gradient(colors: [theme.bellowsA, Color.black.opacity(0.9)]),
                    startPoint: pt(0, a + lightW), endPoint: pt(0, a + fold)))
                // Fold ridge.
                var ridge = Path()
                ridge.move(to: pt(0, a + lightW))
                ridge.addLine(to: pt(length, a + lightW))
                ctx.stroke(ridge, with: .color(.white.opacity(0.10 + shine * 0.3)), lineWidth: 0.8)
            }
            // Tape along both ends and brass corner guards at each fold.
            let tape = max(5, length * 0.012)
            for end in [CGFloat(0), length - tape] {
                ctx.fill(Path(vertical ? CGRect(x: 0, y: end, width: thick, height: tape) : CGRect(x: end, y: 0, width: tape, height: thick)),
                         with: .color(theme.bellowsEdge.opacity(0.92)))
            }
            let guardSize = min(fold * 0.9, 14)
            for i in 0..<n {
                let a = CGFloat(i) * fold + fold * 0.05
                for end in [tape, length - tape - guardSize] {
                    var g = Path()
                    let p0 = pt(end, a), p1 = pt(end + guardSize, a), p2 = pt(end, a + guardSize)
                    let flip = end > length / 2
                    if flip {
                        let q0 = pt(end + guardSize, a), q1 = pt(end, a), q2 = pt(end + guardSize, a + guardSize)
                        g.move(to: q0); g.addLine(to: q1); g.addLine(to: q2)
                    } else {
                        g.move(to: p0); g.addLine(to: p1); g.addLine(to: p2)
                    }
                    g.closeSubpath()
                    ctx.fill(g, with: .linearGradient(Gradient(colors: [theme.trim, theme.trimDark]),
                                                    startPoint: pt(end, a), endPoint: pt(end + guardSize, a + guardSize)))
                }
            }
            // Edge shadows where the bellows meet the boards.
            ctx.fill(Path(rect(0, 3)), with: .color(.black.opacity(0.45)))
            ctx.fill(Path(rect(thick - 3, 3)), with: .color(.black.opacity(0.45)))
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Bellows"))
        .accessibilityValue(Text(direction == .pull ? "Opening" : "Closing"))
    }
}
