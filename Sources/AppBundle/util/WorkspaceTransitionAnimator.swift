import AppKit
import Common

enum SlideDirection {
    case left
    case right
}

@MainActor
func slideOutPosition(for rect: Rect, monitor: Monitor, direction: SlideDirection) -> CGPoint {
    switch direction {
    case .left:
        CGPoint(x: rect.topLeftX - monitor.visibleRect.width, y: rect.topLeftY)
    case .right:
        CGPoint(x: rect.topLeftX + monitor.visibleRect.width, y: rect.topLeftY)
    }
}

@MainActor
func slideInStartPosition(for rect: Rect, monitor: Monitor, direction: SlideDirection) -> CGPoint {
    switch direction {
    case .left:
        CGPoint(x: rect.topLeftX + monitor.visibleRect.width, y: rect.topLeftY)
    case .right:
        CGPoint(x: rect.topLeftX - monitor.visibleRect.width, y: rect.topLeftY)
    }
}
