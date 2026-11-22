import SwiftUI

/// The pleated bellows drawn across the fold. Pleats run parallel to the fold. Each pleat has a lit face and a
/// shadowed face; opening the hinge widens the lit faces, air flow brightens them, and the stroke direction tilts
/// the light. Edge tape and brass corner guards finish each fold, as on a real instrument.
struct BellowsView: View {
    var extension01: Double
    var pressure: Double
    var direction: BellowsDirection
    var vertical: Bool          // strip runs top-to-bottom
    var theme: Theme

    static let pleats = 7

    var body: some View {
        Canvas { ctx, size in
            let length = vertical ? size.height : size.width
            let thick = vertical ? size.width : size.height
            let n = Self.pleats
            let fold = thick / CGFloat(n)
            let open = 0.42 + 0.30 * extension01
            let lean = (direction == .pull ? 1.0 : -1.0) * pressure * 0.08

            func rect(_ a: CGFloat, _ w: CGFloat, from: CGFloat = 0, to: CGFloat? = nil) -> CGRect {
                let l = (to ?? length) - from
                return vertical ? CGRect(x: a, y: from, width: w, height: l) : CGRect(x: from, y: a, width: l, height: w)
            }
            func pt(_ along: CGFloat, _ across: CGFloat) -> CGPoint {
                vertical ? CGPoint(x: across, y: along) : CGPoint(x: along, y: across)
            }

            // Cloth base.
            ctx.fill(Path(rect(0, thick)), with: .color(theme.bellowsA))

            let shine = 0.15 + 0.35 * pressure
            for i in 0..<n {
                let a = CGFloat(i) * fold
                let lit = fold * CGFloat(min(0.85, max(0.2, open + lean)))
                // Lit face: brightest at the ridge.
                ctx.fill(Path(rect(a, lit)), with: .linearGradient(
                    Gradient(stops: [.init(color: theme.bellowsA, location: 0),
                                     .init(color: theme.bellowsB, location: 0.55),
                                     .init(color: theme.bellowsB.opacity(0.9), location: 1)]),
                    startPoint: pt(0, a), endPoint: pt(0, a + lit)))
                ctx.fill(Path(rect(a + lit * 0.45, lit * 0.55)), with: .linearGradient(
                    Gradient(colors: [.white.opacity(0), .white.opacity(shine * 0.45)]),
                    startPoint: pt(0, a + lit * 0.45), endPoint: pt(0, a + lit)))
                // Shadow face.
                ctx.fill(Path(rect(a + lit, fold - lit)), with: .linearGradient(
                    Gradient(colors: [Color.black.opacity(0.85), theme.bellowsA]),
                    startPoint: pt(0, a + lit), endPoint: pt(0, a + fold)))
                // Ridge and valley lines.
                var ridge = Path()
                ridge.move(to: pt(0, a + lit)); ridge.addLine(to: pt(length, a + lit))
                ctx.stroke(ridge, with: .color(theme.bellowsEdge.opacity(0.22 + shine * 0.4)), lineWidth: 1)
                var valley = Path()
                valley.move(to: pt(0, a)); valley.addLine(to: pt(length, a))
                ctx.stroke(valley, with: .color(.black.opacity(0.7)), lineWidth: 1)
            }

            // Edge tape at both ends.
            let tape = max(6, min(14, length * 0.014))
            for end in [CGFloat(0), length - tape] {
                ctx.fill(Path(rect(0, thick, from: end, to: end + tape)), with: .linearGradient(
                    Gradient(colors: [theme.bellowsEdge, theme.bellowsEdge.opacity(0.75)]),
                    startPoint: pt(end, 0), endPoint: pt(end + tape, 0)))
            }
            // Brass corner guards on every ridge, top and bottom.
            let g = min(fold * 0.9, 20)
            for i in 0..<n {
                let a = CGFloat(i) * fold + fold * 0.05
                for top in [true, false] {
                    let base = top ? tape : length - tape
                    let tip = top ? base + g : base - g
                    var p = Path()
                    p.move(to: pt(base, a))
                    p.addLine(to: pt(base, a + g))
                    p.addLine(to: pt(tip, a + g * 0.5))
                    p.closeSubpath()
                    ctx.fill(p, with: .linearGradient(Gradient(colors: [theme.trim, theme.trimDark]),
                                                    startPoint: pt(base, a), endPoint: pt(tip, a + g)))
                    ctx.stroke(p, with: .color(.black.opacity(0.35)), lineWidth: 0.6)
                }
            }
            // Where the bellows meet the boards.
            ctx.fill(Path(rect(0, 2.5)), with: .color(.black.opacity(0.55)))
            ctx.fill(Path(rect(thick - 2.5, 2.5)), with: .color(.black.opacity(0.55)))
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Bellows"))
        .accessibilityValue(Text(direction == .pull ? LocalizedStringKey("Opening") : LocalizedStringKey("Closing")))
    }
}
