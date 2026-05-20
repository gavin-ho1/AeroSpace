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
        CGPoint(x: -rect.width, y: rect.topLeftY)
    case .right:
        CGPoint(x: monitor.visibleRect.maxX + 1, y: rect.topLeftY)
    }
}

@MainActor
func slideInStartPosition(for rect: Rect, monitor: Monitor, direction: SlideDirection) -> CGPoint {
    switch direction {
    case .left:
        CGPoint(x: monitor.visibleRect.maxX + 1, y: rect.topLeftY)
    case .right:
        CGPoint(x: -rect.width, y: rect.topLeftY)
    }
}
