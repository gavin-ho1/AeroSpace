import AppKit
import Foundation

@MainActor
final class WindowAnimation {
    let windowId: UInt32
    let app: MacApp
    var springX: SpringAnimation
    var springY: SpringAnimation
    var springW: SpringAnimation
    var springH: SpringAnimation
    var targetRect: CGRect
    var revision: Int = 0

    init(
        windowId: UInt32,
        app: MacApp,
        springX: SpringAnimation,
        springY: SpringAnimation,
        springW: SpringAnimation,
        springH: SpringAnimation,
        targetRect: CGRect
    ) {
        self.windowId = windowId
        self.app = app
        self.springX = springX
        self.springY = springY
        self.springW = springW
        self.springH = springH
        self.targetRect = targetRect
    }
}

private struct PendingWindowAnimation {
    var targetTopLeft: CGPoint?
    var targetSize: CGSize?
    var sourceRect: Rect?
}

@MainActor
final class WindowAnimator {
    static let shared = WindowAnimator()
    static let workspaceTransitionCleanupDelayNanoseconds: UInt64 = 300_000_000

    private var activeAnimations: [UInt32: WindowAnimation] = [:]
    private var pendingTargets: [UInt32: PendingWindowAnimation] = [:]
    private var isLoopRunning = false

    private init() {}

    func cancelAnimation(for windowId: UInt32) {
        activeAnimations.removeValue(forKey: windowId)
        pendingTargets.removeValue(forKey: windowId)
    }

    func isAnimating(windowId: UInt32) -> Bool {
        activeAnimations[windowId] != nil || pendingTargets[windowId] != nil
    }

    func animate(windowId: UInt32, app: MacApp, targetTopLeft: CGPoint?, targetSize: CGSize?, sourceRect: Rect? = nil) {
        if let existing = activeAnimations[windowId] {
            let now = CACurrentMediaTime()
            let currentX = existing.springX.value(at: now)
            let currentVelX = existing.springX.velocity(at: now)

            let currentY = existing.springY.value(at: now)
            let currentVelY = existing.springY.velocity(at: now)

            let currentW = existing.springW.value(at: now)
            let currentVelW = existing.springW.velocity(at: now)

            let currentH = existing.springH.value(at: now)
            let currentVelH = existing.springH.velocity(at: now)

            let targetX = targetTopLeft?.x ?? existing.targetRect.minX
            let targetY = targetTopLeft?.y ?? existing.targetRect.minY
            let targetW = targetSize?.width ?? existing.targetRect.width
            let targetH = targetSize?.height ?? existing.targetRect.height

            let config = SpringConfig.niriWindowMovement
            existing.springX = SpringAnimation(from: currentX, to: targetX, initialVelocity: currentVelX, startTime: now, config: config)
            existing.springY = SpringAnimation(from: currentY, to: targetY, initialVelocity: currentVelY, startTime: now, config: config)
            existing.springW = SpringAnimation(from: currentW, to: targetW, initialVelocity: currentVelW, startTime: now, config: config)
            existing.springH = SpringAnimation(from: currentH, to: targetH, initialVelocity: currentVelH, startTime: now, config: config)
            existing.targetRect = CGRect(x: targetX, y: targetY, width: targetW, height: targetH)
            existing.revision += 1
            return
        }

        if let old = pendingTargets[windowId] {
            let mergedTopLeft = targetTopLeft ?? old.targetTopLeft
            let mergedSize = targetSize ?? old.targetSize
            pendingTargets[windowId] = PendingWindowAnimation(
                targetTopLeft: mergedTopLeft,
                targetSize: mergedSize,
                sourceRect: old.sourceRect ?? sourceRect
            )
            return
        }

        pendingTargets[windowId] = PendingWindowAnimation(targetTopLeft: targetTopLeft, targetSize: targetSize, sourceRect: sourceRect)

        if let sourceRect {
            guard let target = pendingTargets.removeValue(forKey: windowId) else { return }
            startAnimation(windowId: windowId, app: app, sourceRect: sourceRect, target: target)
            return
        }

        Task { @MainActor in
            guard let rect = try? await app.getAxRect(windowId) else {
                if let target = pendingTargets.removeValue(forKey: windowId) {
                    app.setAxFrameInstant(windowId, target.targetTopLeft, target.targetSize)
                }
                return
            }

            guard let target = pendingTargets.removeValue(forKey: windowId) else { return }
            startAnimation(windowId: windowId, app: app, sourceRect: target.sourceRect ?? rect, target: target)
        }
    }

    private func startAnimation(windowId: UInt32, app: MacApp, sourceRect: Rect, target: PendingWindowAnimation) {
        let now = CACurrentMediaTime()
        let currentX = Double(sourceRect.topLeftX)
        let currentY = Double(sourceRect.topLeftY)
        let currentW = Double(sourceRect.width)
        let currentH = Double(sourceRect.height)

        let targetX = Double(target.targetTopLeft?.x ?? sourceRect.topLeftX)
        let targetY = Double(target.targetTopLeft?.y ?? sourceRect.topLeftY)
        let targetW = Double(target.targetSize?.width ?? sourceRect.width)
        let targetH = Double(target.targetSize?.height ?? sourceRect.height)

        let config = SpringConfig.niriWindowMovement
        let anim = WindowAnimation(
            windowId: windowId,
            app: app,
            springX: SpringAnimation(from: currentX, to: targetX, startTime: now, config: config),
            springY: SpringAnimation(from: currentY, to: targetY, startTime: now, config: config),
            springW: SpringAnimation(from: currentW, to: targetW, startTime: now, config: config),
            springH: SpringAnimation(from: currentH, to: targetH, startTime: now, config: config),
            targetRect: CGRect(x: targetX, y: targetY, width: targetW, height: targetH)
        )

        activeAnimations[windowId] = anim
        startLoopIfNeeded()
    }

    private func startLoopIfNeeded() {
        guard !isLoopRunning else { return }
        isLoopRunning = true

        Task { @MainActor in
            while !activeAnimations.isEmpty {
                let frameStart = CACurrentMediaTime()
                var completedIds: [UInt32] = []
                let frameAnimations = activeAnimations.map { ($0.key, $0.value) }

                for (windowId, anim) in frameAnimations where activeAnimations[windowId] === anim {
                    let now = CACurrentMediaTime()
                    let revision = anim.revision
                    let doneX = anim.springX.isComplete(at: now)
                    let doneY = anim.springY.isComplete(at: now)
                    let doneW = anim.springW.isComplete(at: now)
                    let doneH = anim.springH.isComplete(at: now)

                    if doneX && doneY && doneW && doneH {
                        try? await anim.app.setAxFrameBlockingForAnimation(windowId, anim.targetRect.origin, anim.targetRect.size)
                        if activeAnimations[windowId] === anim && anim.revision == revision {
                            completedIds.append(windowId)
                        }
                    } else {
                        let curX = anim.springX.value(at: now)
                        let curY = anim.springY.value(at: now)
                        let curW = anim.springW.value(at: now)
                        let curH = anim.springH.value(at: now)

                        try? await anim.app.setAxFrameBlockingForAnimation(
                            windowId,
                            CGPoint(x: curX, y: curY),
                            CGSize(width: curW, height: curH)
                        )
                    }
                }

                for id in completedIds {
                    activeAnimations.removeValue(forKey: id)
                }

                let elapsed = CACurrentMediaTime() - frameStart
                let sleepTime = max(0, 1.0 / 60.0 - elapsed)
                if sleepTime > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(sleepTime * 1_000_000_000))
                }
            }
            isLoopRunning = false
        }
    }
}
