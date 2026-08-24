#if canImport(UIKit)
import Observation
import SwiftUI

@MainActor
@Observable
final class FanPickerController {
    struct RevealSession {
        let id = UUID()
        let startDate: Date
        let assets: [RecentPhotoAsset]
        let geometry: ResolvedFanPickerGeometry
    }

    struct DismissSession {
        let reveal: RevealSession
        let startDate: Date
        let initialRevealElapsed: TimeInterval
        let highlightedID: String?
    }

    enum PresentationPhase {
        case revealing
        case settled
        case frozen(revealElapsed: TimeInterval)
        case dismissing(startDate: Date, initialRevealElapsed: TimeInterval)
    }

    struct Presentation {
        let session: RevealSession
        let phase: PresentationPhase
        let highlightedID: String?
    }

    enum State {
        case idle
        case revealing(RevealSession, highlightedID: String?)
        case open(RevealSession, highlightedID: String?)
        case dismissing(DismissSession)
    }

    private(set) var state: State = .idle
    private(set) var revealFeedbackToken = 0
    private(set) var hoverFeedbackToken = 0

    @ObservationIgnored
    private var geometry = ResolvedFanPickerGeometry()
    @ObservationIgnored
    private var settleTask: Task<Void, Never>?

    var isActive: Bool {
        if case .idle = state { false } else { true }
    }

    var showsCloseTrigger: Bool {
        switch state {
        case .revealing, .open:
            true
        case .idle, .dismissing:
            false
        }
    }

    var presentation: Presentation? {
        switch state {
        case .idle:
            nil
        case let .revealing(session, highlightedID):
            Presentation(
                session: session,
                phase: .revealing,
                highlightedID: highlightedID
            )
        case let .open(session, highlightedID):
            Presentation(
                session: session,
                phase: .settled,
                highlightedID: highlightedID
            )
        case let .dismissing(session):
            Presentation(
                session: session.reveal,
                phase: .dismissing(
                    startDate: session.startDate,
                    initialRevealElapsed: session.initialRevealElapsed
                ),
                highlightedID: session.highlightedID
            )
        }
    }

    func updateGeometry(_ geometry: ResolvedFanPickerGeometry) {
        self.geometry = geometry
    }

    func begin(
        assets: [RecentPhotoAsset],
        configuration: FanPickerConfiguration,
        reduceMotion: Bool = false,
        now: Date = .now
    ) {
        guard case .idle = state, geometry.isValid, !assets.isEmpty else { return }

        let visibleAssets = Array(assets.prefix(max(configuration.itemCount, 0)))
        guard !visibleAssets.isEmpty else { return }

        let session = RevealSession(
            startDate: now,
            assets: visibleAssets,
            geometry: geometry
        )
        state = reduceMotion
            ? .open(session, highlightedID: nil)
            : .revealing(session, highlightedID: nil)
        session.assets.forEach { $0.beginImageFreeze() }
        revealFeedbackToken += 1

        settleTask?.cancel()
        guard !reduceMotion else {
            settleTask = nil
            return
        }

        let duration = RevealMotionTimeline(configuration: configuration)
            .duration(itemCount: visibleAssets.count)
        settleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.markRevealSettled(sessionID: session.id)
        }
    }

    func updateHover(
        at point: CGPoint,
        configuration: FanPickerConfiguration,
        now: Date = .now
    ) {
        let session: RevealSession
        let currentID: String?
        let isRevealing: Bool
        switch state {
        case let .revealing(currentSession, highlightedID):
            session = currentSession
            currentID = highlightedID
            isRevealing = true
        case let .open(currentSession, highlightedID):
            session = currentSession
            currentID = highlightedID
            isRevealing = false
        case .idle, .dismissing:
            return
        }

        let rects = visualRects(
            for: session,
            configuration: configuration,
            now: now,
            isRevealing: isRevealing
        )
        let pairs = Array(zip(session.assets, rects))

        let nextID: String?
        if let currentID,
           let currentRect = pairs.first(where: { $0.0.id == currentID })?.1,
           currentRect
            .insetBy(
                dx: -configuration.hoverStickyExpansion,
                dy: -configuration.hoverStickyExpansion
            )
            .contains(point) {
            nextID = currentID
        } else {
            nextID = pairs.first { _, rect in
                rect
                    .insetBy(
                        dx: -configuration.hoverHitExpansion,
                        dy: -configuration.hoverHitExpansion
                    )
                    .contains(point)
            }?.0.id
        }

        guard nextID != currentID else { return }
        state = isRevealing
            ? .revealing(session, highlightedID: nextID)
            : .open(session, highlightedID: nextID)
        if nextID != nil {
            hoverFeedbackToken += 1
        }
    }

    func releaseSelection() -> RecentPhotoAsset? {
        let session: RevealSession
        let highlightedID: String?
        switch state {
        case let .revealing(currentSession, currentID),
             let .open(currentSession, currentID):
            session = currentSession
            highlightedID = currentID
        case .idle, .dismissing:
            return nil
        }

        return session.assets.first { $0.id == highlightedID }
    }

    func frozenPresentation(now: Date = .now) -> Presentation? {
        switch state {
        case .idle:
            nil
        case let .revealing(session, highlightedID):
            Presentation(
                session: session,
                phase: .frozen(
                    revealElapsed: max(now.timeIntervalSince(session.startDate), 0)
                ),
                highlightedID: highlightedID
            )
        case let .open(session, highlightedID):
            Presentation(
                session: session,
                phase: .settled,
                highlightedID: highlightedID
            )
        case let .dismissing(session):
            Presentation(
                session: session.reveal,
                phase: .dismissing(
                    startDate: session.startDate,
                    initialRevealElapsed: session.initialRevealElapsed
                ),
                highlightedID: session.highlightedID
            )
        }
    }

    func commitSelection() {
        switch state {
        case let .revealing(session, _), let .open(session, _):
            settleTask?.cancel()
            settleTask = nil
            session.assets.forEach { $0.endImageFreeze() }
            state = .idle
        case .idle, .dismissing:
            break
        }
    }

    func cancelImmediately() {
        let activeAssets: [RecentPhotoAsset]
        switch state {
        case .idle:
            activeAssets = []
        case let .revealing(session, _), let .open(session, _):
            activeAssets = session.assets
        case let .dismissing(session):
            activeAssets = session.reveal.assets
        }
        settleTask?.cancel()
        settleTask = nil
        state = .idle
        activeAssets.forEach { $0.endImageFreeze() }
    }

    func dismiss(
        configuration: FanPickerConfiguration,
        now: Date = .now
    ) {
        let session: RevealSession
        let highlightedID: String?
        let initialRevealElapsed: TimeInterval
        let revealDuration: TimeInterval

        switch state {
        case .idle, .dismissing:
            return
        case let .revealing(currentSession, currentID):
            session = currentSession
            highlightedID = currentID
            revealDuration = RevealMotionTimeline(configuration: configuration)
                .duration(itemCount: currentSession.assets.count)
            initialRevealElapsed = min(
                max(now.timeIntervalSince(currentSession.startDate), 0),
                revealDuration
            )
        case let .open(currentSession, currentID):
            session = currentSession
            highlightedID = currentID
            revealDuration = RevealMotionTimeline(configuration: configuration)
                .duration(itemCount: currentSession.assets.count)
            initialRevealElapsed = revealDuration
        }

        settleTask?.cancel()
        state = .dismissing(
            DismissSession(
                reveal: session,
                startDate: now,
                initialRevealElapsed: initialRevealElapsed,
                highlightedID: highlightedID
            )
        )
        let dismissalDuration = RevealMotionTimeline(configuration: configuration)
            .dismissalDuration(itemCount: session.assets.count)
        settleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(dismissalDuration))
            guard !Task.isCancelled else { return }
            self?.finishDismissal(sessionID: session.id)
        }
    }

    private func markRevealSettled(sessionID: UUID) {
        guard case let .revealing(session, highlightedID) = state,
              session.id == sessionID else {
            return
        }
        state = .open(session, highlightedID: highlightedID)
        settleTask = nil
    }

    private func finishDismissal(sessionID: UUID) {
        guard case let .dismissing(session) = state,
              session.reveal.id == sessionID else {
            return
        }
        session.reveal.assets.forEach { $0.endImageFreeze() }
        state = .idle
        settleTask = nil
    }

    private func visualRects(
        for session: RevealSession,
        configuration: FanPickerConfiguration,
        now: Date,
        isRevealing: Bool
    ) -> [CGRect] {
        let destinations = session.geometry.recentRects(
            count: session.assets.count,
            configuration: configuration
        )
        guard isRevealing else { return destinations }

        let source = CGPoint(
            x: session.geometry.triggerRect.midX,
            y: session.geometry.triggerRect.midY
        )
        let elapsed = max(now.timeIntervalSince(session.startDate), 0)
        let timeline = RevealMotionTimeline(configuration: configuration)

        return destinations.enumerated().map { index, destination in
            let motion = timeline.value(
                source: source,
                destination: CGPoint(x: destination.midX, y: destination.midY),
                index: index,
                time: elapsed
            )
            let size = configuration.recentSize * motion.scale
            return CGRect(
                x: motion.center.x - size / 2,
                y: motion.center.y - size / 2,
                width: size,
                height: size
            )
        }
    }
}
#endif
