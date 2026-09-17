import SwiftUI
import UIKit

/// Gesture surface for the unified timeline plot.
///
/// Browse mode lets the parent diary `ScrollView` keep vertical scrolling:
/// a one-finger pan only begins when the movement is clearly horizontal, so
/// a vertical flick rolls the whole diary instead of trapping the user on
/// the chart. Select mode claims the pan exclusively (any direction) so a
/// drag paints a time range and the page cannot scroll underneath.
struct TimelineChartGestures: UIViewRepresentable {
    enum Mode {
        case browse
        case select
    }

    var mode: Mode
    var panEnabled: Bool
    var pinchEnabled: Bool
    var onTap: (CGPoint) -> Void
    var onPanChanged: (CGPoint, CGSize) -> Void
    var onPanEnded: (CGPoint, CGSize) -> Void
    var onPinchChanged: (CGFloat, CGPoint) -> Void
    var onPinchEnded: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        context.coordinator.attach(to: view)
        context.coordinator.update(from: self)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.update(from: self)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var spec: TimelineChartGestures?
        let tap = UITapGestureRecognizer()
        let pan = UIPanGestureRecognizer()
        let pinch = UIPinchGestureRecognizer()

        func attach(to view: UIView) {
            tap.addTarget(self, action: #selector(handleTap))
            pan.addTarget(self, action: #selector(handlePan))
            pinch.addTarget(self, action: #selector(handlePinch))
            tap.delegate = self
            pan.delegate = self
            pinch.delegate = self
            pan.maximumNumberOfTouches = 1
            pan.cancelsTouchesInView = false
            tap.cancelsTouchesInView = false
            pinch.cancelsTouchesInView = false
            view.addGestureRecognizer(tap)
            view.addGestureRecognizer(pan)
            view.addGestureRecognizer(pinch)
        }

        func update(from spec: TimelineChartGestures) {
            self.spec = spec
            pan.isEnabled = spec.panEnabled
            pinch.isEnabled = spec.pinchEnabled
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            spec?.onTap(gesture.location(in: gesture.view))
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            let location = gesture.location(in: view)
            let translation = gesture.translation(in: view)
            let size = CGSize(width: translation.x, height: translation.y)
            switch gesture.state {
            case .began, .changed:
                spec?.onPanChanged(location, size)
            default:
                spec?.onPanEnded(location, size)
            }
        }

        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let view = gesture.view else { return }
            switch gesture.state {
            case .began, .changed:
                spec?.onPinchChanged(gesture.scale, gesture.location(in: view))
            default:
                spec?.onPinchEnded()
            }
        }

        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let spec else { return false }
            if gesture === pan {
                guard spec.panEnabled else { return false }
                if spec.mode == .select { return true }
                guard let pan = gesture as? UIPanGestureRecognizer else { return false }
                let translation = pan.translation(in: pan.view)
                if hypot(translation.x, translation.y) > 2 {
                    return abs(translation.x) > abs(translation.y)
                }
                let velocity = pan.velocity(in: pan.view)
                return abs(velocity.x) > abs(velocity.y)
            }
            if gesture === pinch { return spec.pinchEnabled }
            return true
        }

        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            if gesture === pinch || other === pinch { return false }
            if spec?.mode == .select { return false }
            if gesture === tap { return true }
            return false
        }

        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            spec?.mode == .select && gesture === pan && other.view is UIScrollView
        }
    }
}

/// When true, the diary page `ScrollView` must not move — used while the
/// timeline is in range-select mode.
struct TimelineBlocksScrollKey: PreferenceKey {
    static var defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}
