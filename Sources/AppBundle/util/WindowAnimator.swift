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

@MainActor
final class WindowAnimator {
    static let shared = WindowAnimator()

    private var activeAnimations: [UInt32: WindowAnimation] = [:]
    private var pendingTargets: [UInt32: (CGPoint?, CGSize?)] = [:]
    private var isLoopRunning = false

    private init() {}

    func cancelAnimation(for windowId: UInt32) {
        activeAnimations.removeValue(forKey: windowId)
        pendingTargets.removeValue(forKey: windowId)
    }

    func isAnimating(windowId: UInt32) -> Bool {
        activeAnimations[windowId] != nil || pendingTargets[windowId] != nil
    }

    func animate(windowId: UInt32, app: MacApp, targetTopLeft: CGPoint?, targetSize: CGSize?) {
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
            return
        }

        if let old = pendingTargets[windowId] {
            let mergedTopLeft = targetTopLeft ?? old.0
            let mergedSize = targetSize ?? old.1
            pendingTargets[windowId] = (mergedTopLeft, mergedSize)
            return
        }

        pendingTargets[windowId] = (targetTopLeft, targetSize)

        Task { @MainActor in
            guard let rect = try? await app.getAxRect(windowId) else {
                if let target = pendingTargets.removeValue(forKey: windowId) {
                    app.setAxFrameInstant(windowId, target.0, target.1)
                }
                return
            }

            guard let target = pendingTargets.removeValue(forKey: windowId) else { return }

            let now = CACurrentMediaTime()
            let currentX = Double(rect.topLeftX)
            let currentY = Double(rect.topLeftY)
            let currentW = Double(rect.width)
            let currentH = Double(rect.height)

            let targetX = Double(target.0?.x ?? rect.topLeftX)
            let targetY = Double(target.0?.y ?? rect.topLeftY)
            let targetW = Double(target.1?.width ?? rect.width)
            let targetH = Double(target.1?.height ?? rect.height)

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
    }

    private func startLoopIfNeeded() {
        guard !isLoopRunning else { return }
        isLoopRunning = true

        Task { @MainActor in
            while !activeAnimations.isEmpty {
                let now = CACurrentMediaTime()
                var completedIds: [UInt32] = []

                for (windowId, anim) in activeAnimations {
                    let doneX = anim.springX.isComplete(at: now)
                    let doneY = anim.springY.isComplete(at: now)
                    let doneW = anim.springW.isComplete(at: now)
                    let doneH = anim.springH.isComplete(at: now)

                    if doneX && doneY && doneW && doneH {
                        anim.app.setAxFrameInstant(windowId, anim.targetRect.origin, anim.targetRect.size)
                        completedIds.append(windowId)
                    } else {
                        let curX = anim.springX.value(at: now)
                        let curY = anim.springY.value(at: now)
                        let curW = anim.springW.value(at: now)
                        let curH = anim.springH.value(at: now)

                        anim.app.setAxFrameInstant(
                            windowId,
                            CGPoint(x: curX, y: curY),
                            CGSize(width: curW, height: curH)
                        )
                    }
                }

                for id in completedIds {
                    activeAnimations.removeValue(forKey: id)
                }

                try? await Task.sleep(nanoseconds: 16_666_667) // ~60 FPS
            }
            isLoopRunning = false
        }
    }
}
