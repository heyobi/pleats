import SwiftUI

/// Feeds the iPhone Duo hinge (iOS 27.1) into the instrument. Elsewhere it does nothing.
struct HingeReader: ViewModifier {
    let instrument: Instrument

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, ctx in
                let h: DeviceHinge? = ctx.hinge
                guard let h else { return }
                let closed = h.status == .closed
                instrument.hingeChanged(angle: h.angle.degrees, closed: closed, present: true)
            }
        } else {
            content
        }
    }
}

/// The division (fold) reserved region of an iPhone Duo in this geometry's coordinates, if any.
func foldFrame(_ proxy: GeometryProxy) -> CGRect? {
    if #available(iOS 27.1, *) {
        if let d = proxy.reservedRegions(kind: .division, options: [.includeInactive]).first {
            return d.frame
        }
    }
    return nil
}
