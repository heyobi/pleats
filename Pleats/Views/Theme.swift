import SwiftUI

/// Materials of the instrument. Dark: black lacquer, brass and ivory pearl. Light: ivory celluloid, gold and
/// bordeaux bellows.
struct Theme {
    let bodyTop: Color
    let bodyBottom: Color
    let fleck: Color
    let trim: Color
    let trimDark: Color
    let bellowsA: Color
    let bellowsB: Color
    let bellowsEdge: Color
    let ink: Color
    let subtle: Color
    let glow: Color
    let pushGlow: Color

    static func of(_ scheme: ColorScheme) -> Theme {
        scheme == .dark
            ? Theme(bodyTop: Color(red: 0.12, green: 0.05, blue: 0.07), bodyBottom: Color(red: 0.04, green: 0.02, blue: 0.03),
                    fleck: Color(red: 1, green: 0.85, blue: 0.75),
                    trim: Color(red: 0.86, green: 0.70, blue: 0.40), trimDark: Color(red: 0.45, green: 0.33, blue: 0.14),
                    bellowsA: Color(red: 0.05, green: 0.03, blue: 0.035), bellowsB: Color(red: 0.36, green: 0.09, blue: 0.12),
                    bellowsEdge: Color(red: 0.90, green: 0.86, blue: 0.80),
                    ink: Color(red: 0.98, green: 0.94, blue: 0.86), subtle: Color(red: 0.98, green: 0.94, blue: 0.86).opacity(0.62),
                    glow: Color(red: 1.0, green: 0.78, blue: 0.32), pushGlow: Color(red: 0.45, green: 0.80, blue: 1.0))
            : Theme(bodyTop: Color(red: 0.97, green: 0.94, blue: 0.88), bodyBottom: Color(red: 0.88, green: 0.83, blue: 0.74),
                    fleck: Color(red: 0.70, green: 0.55, blue: 0.40),
                    trim: Color(red: 0.70, green: 0.53, blue: 0.22), trimDark: Color(red: 0.42, green: 0.30, blue: 0.10),
                    bellowsA: Color(red: 0.42, green: 0.06, blue: 0.11), bellowsB: Color(red: 0.62, green: 0.13, blue: 0.19),
                    bellowsEdge: Color(red: 0.98, green: 0.95, blue: 0.88),
                    ink: Color(red: 0.22, green: 0.10, blue: 0.08), subtle: Color(red: 0.22, green: 0.10, blue: 0.08).opacity(0.6),
                    glow: Color(red: 0.95, green: 0.62, blue: 0.05), pushGlow: Color(red: 0.10, green: 0.50, blue: 0.90))
    }
}

/// Lacquered body with fine pearloid flecks and a brass inlay line.
struct BodyPanel: View {
    var theme: Theme
    var corner: CGFloat = 18

    var body: some View {
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            ctx.fill(Path(rect), with: .linearGradient(Gradient(colors: [theme.bodyTop, theme.bodyBottom]),
                                                      startPoint: .zero, endPoint: CGPoint(x: size.width * 0.3, y: size.height)))
            // Pearloid flecks: deterministic, sparse and faint.
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func rnd() -> CGFloat {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1)
            }
            let count = Int(size.width * size.height / 900)
            for _ in 0..<count {
                let x = rnd() * size.width, y = rnd() * size.height
                let r = 0.4 + rnd() * 1.3
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2.2, height: r)),
                         with: .color(theme.fleck.opacity(0.035 + Double(rnd()) * 0.05)))
            }
            // Sheen.
            ctx.fill(Path(rect), with: .radialGradient(Gradient(colors: [.white.opacity(0.10), .clear]),
                                                      center: CGPoint(x: size.width * 0.25, y: size.height * 0.1),
                                                      startRadius: 0, endRadius: max(size.width, size.height) * 0.8))
            // Brass inlay.
            let inset = rect.insetBy(dx: 7, dy: 7)
            ctx.stroke(Path(roundedRect: inset, cornerRadius: max(4, corner - 7)), with: .color(theme.trim.opacity(0.55)), lineWidth: 1)
        }
    }
}

/// Draws one pearl (or ebony) button into a Canvas.
enum PearlPainter {
    static func draw(_ ctx: inout GraphicsContext, center c: CGPoint, diameter d: CGFloat, ebony: Bool, pressed: Bool, theme: Theme) {
        let r = d / 2 * (pressed ? 0.94 : 1)
        let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
        let circle = Path(ellipseIn: rect)

        // Shadow under the button (a raised button casts a longer one).
        var shadow = ctx
        shadow.addFilter(.blur(radius: pressed ? 1.2 : 2.6))
        let off: CGFloat = pressed ? 0.8 : 2.4
        shadow.fill(Path(ellipseIn: rect.offsetBy(dx: 0, dy: off)), with: .color(.black.opacity(pressed ? 0.35 : 0.5)))

        // Brass ring.
        ctx.fill(Path(ellipseIn: rect.insetBy(dx: -1.6, dy: -1.6)),
                 with: .linearGradient(Gradient(colors: [theme.trim, theme.trimDark]), startPoint: CGPoint(x: c.x, y: rect.minY), endPoint: CGPoint(x: c.x, y: rect.maxY)))

        if ebony {
            ctx.fill(circle, with: .radialGradient(Gradient(colors: [Color(white: 0.32), Color(white: 0.08), Color(white: 0.02)]),
                                                  center: CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.35), startRadius: 0, endRadius: r * 1.3))
        } else {
            // Mother-of-pearl: warm white with drifting iridescence.
            ctx.fill(circle, with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.99, blue: 0.97),
                                                                      Color(red: 0.95, green: 0.92, blue: 0.88),
                                                                      Color(red: 0.80, green: 0.76, blue: 0.72)]),
                                                  center: CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.35), startRadius: 0, endRadius: r * 1.25))
            var iri = ctx
            iri.opacity = 0.22
            iri.blendMode = .overlay
            let hue = Double((c.x * 0.013 + c.y * 0.007).truncatingRemainder(dividingBy: 1))
            iri.fill(circle, with: .conicGradient(Gradient(colors: [
                Color(hue: hue, saturation: 0.55, brightness: 1),
                Color(hue: (hue + 0.33).truncatingRemainder(dividingBy: 1), saturation: 0.45, brightness: 1),
                Color(hue: (hue + 0.66).truncatingRemainder(dividingBy: 1), saturation: 0.55, brightness: 1),
                Color(hue: hue, saturation: 0.55, brightness: 1)]), center: c, angle: .degrees(hue * 360)))
        }
        // Dished top: highlight on the upper rim, shade on the lower.
        ctx.stroke(Path(ellipseIn: rect.insetBy(dx: r * 0.12, dy: r * 0.12)),
                   with: .linearGradient(Gradient(colors: [.black.opacity(ebony ? 0.5 : 0.12), .white.opacity(ebony ? 0.18 : 0.7)]),
                                         startPoint: CGPoint(x: c.x, y: rect.minY), endPoint: CGPoint(x: c.x, y: rect.maxY)),
                   lineWidth: max(1, r * 0.08))
        if pressed {
            ctx.fill(circle, with: .color(.black.opacity(ebony ? 0.2 : 0.12)))
        }
    }

    /// A glowing ring around a button the lesson wants next.
    static func glow(_ ctx: inout GraphicsContext, center c: CGPoint, diameter d: CGFloat, color: Color, strength: Double, pulse: Double) {
        let r = d / 2 + 4 + CGFloat(pulse) * 3
        let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
        var g = ctx
        g.addFilter(.blur(radius: 6))
        g.stroke(Path(ellipseIn: rect), with: .color(color.opacity(0.75 * strength)), lineWidth: 6)
        ctx.stroke(Path(ellipseIn: rect), with: .color(color.opacity(strength)), lineWidth: 2.5)
    }
}

extension View {
    /// Small round control with a brass rim, used in the control bar.
    func brassControl(_ theme: Theme, active: Bool = false) -> some View {
        self
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(active ? theme.bodyBottom : theme.ink)
            .frame(width: 40, height: 40)
            .background(Circle().fill(active ? AnyShapeStyle(theme.trim) : AnyShapeStyle(.ultraThinMaterial)))
            .overlay(Circle().stroke(theme.trim.opacity(0.8), lineWidth: 1))
            .contentShape(Circle())
    }
}
