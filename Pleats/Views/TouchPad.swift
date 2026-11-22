import SwiftUI
import UIKit

/// A transparent multi-touch surface. Reports every finger's position on each change, so the board can press
/// several buttons at once and slide from one button to the next. UIKit touches arrive without gesture
/// recognizer delays, which keeps the instrument responsive.
struct TouchPad: UIViewRepresentable {
    var onTouches: ([CGPoint]) -> Void

    func makeUIView(context: Context) -> TouchView {
        let v = TouchView()
        v.onTouches = onTouches
        return v
    }

    func updateUIView(_ v: TouchView, context: Context) { v.onTouches = onTouches }

    final class TouchView: UIView {
        var onTouches: ([CGPoint]) -> Void = { _ in }
        private var active = Set<UITouch>()

        override init(frame: CGRect) {
            super.init(frame: frame)
            isMultipleTouchEnabled = true
            isExclusiveTouch = false
            backgroundColor = .clear
        }
        required init?(coder: NSCoder) { fatalError() }

        private func report() { onTouches(active.map { $0.location(in: self) }) }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { active.formUnion(touches); report() }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { report() }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { active.subtract(touches); report() }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { active.subtract(touches); report() }
    }
}

/// A drag surface for the bellows: reports movement along one axis.
struct BellowsPad: UIViewRepresentable {
    var vertical: Bool      // true: drag up/down
    var onDelta: (CGFloat) -> Void

    func makeUIView(context: Context) -> PadView {
        let v = PadView()
        v.vertical = vertical
        v.onDelta = onDelta
        return v
    }

    func updateUIView(_ v: PadView, context: Context) {
        v.vertical = vertical
        v.onDelta = onDelta
    }

    final class PadView: UIView {
        var vertical = false
        var onDelta: (CGFloat) -> Void = { _ in }
        private var last: CGPoint?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isMultipleTouchEnabled = false
            backgroundColor = .clear
        }
        required init?(coder: NSCoder) { fatalError() }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { last = touches.first?.location(in: self) }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let t = touches.first, let l = last else { return }
            let p = t.location(in: self)
            onDelta(vertical ? p.y - l.y : p.x - l.x)
            last = p
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { last = nil }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { last = nil }
    }
}
