#if canImport(UIKit)
import Observation
import SwiftUI

@MainActor
@Observable
final class FanPickerController {
    private(set) var state: State = .idle
    private(set) var revealFeedbackToken = 0
    private(set) var hoverFeedbackToken = 0

    @ObservationIgnored
    private var geometry = ResolvedFanPickerGeometry()
    @ObservationIgnored
    private var settleTask: Task<Void, Never>?
    @ObservationIgnored
    private var hasSyncedRevealClock = false

    var isActive: Bool {
        if case .idle = state { false } else { true }
    }

    var isOpen: Bool {
        if case .open = state { true } else { false }
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
}

extension FanPickerController {
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

        let assetLimit = configuration.scrolling?.resolvedAssetLimit
            ?? configuration.itemCount
        let visibleAssets = Array(assets.prefix(max(assetLimit, 0)))
        guard !visibleAssets.isEmpty else { return }
        let frozenAssets = visibleAssets.filter(\.isDisplayReady)

        let revealItemCount = min(
            max(configuration.itemCount, 0),
            visibleAssets.count
        )
        let session = RevealSession(
            startDate: now,
            assets: visibleAssets,
            frozenAssets: frozenAssets,
            revealItemCount: revealItemCount,
            revealMotionItemCount: FanPickerRevealGeometry.openingMotionItemCount(
                geometry: geometry,
                revealItemCount: revealItemCount,
                assetCount: visibleAssets.count,
                configuration: configuration
            ),
            geometry: geometry
        )
        state = reduceMotion
            ? .open(session, highlightedID: nil)
            : .revealing(session, highlightedID: nil)
        hasSyncedRevealClock = false
        frozenAssets.forEach { $0.beginImageFreeze() }
        revealFeedbackToken += 1

        settleTask?.cancel()
        guard !reduceMotion else {
            settleTask = nil
            return
        }

        let duration = RevealMotionTimeline(configuration: configuration)
            .duration(itemCount: session.revealItemCount)
        settleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.markRevealSettled(sessionID: session.id)
        }
    }

    // Start timing when the overlay can render, not when the hold is recognized.
    func syncRevealClock(
        configuration: FanPickerConfiguration,
        now: Date = .now
    ) {
        guard case .revealing(var session, let highlightedID) = state,
              !hasSyncedRevealClock else {
            return
        }
        hasSyncedRevealClock = true
        guard now > session.startDate else { return }

        session.startDate = now
        state = .revealing(session, highlightedID: highlightedID)
        settleTask?.cancel()
        let duration = RevealMotionTimeline(configuration: configuration)
            .duration(itemCount: session.revealItemCount)
        settleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.markRevealSettled(sessionID: session.id)
        }
    }
}

extension FanPickerController {
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

        let rects = FanPickerRevealGeometry.visualRects(
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

    func updateHover(assetID: String?) {
        switch state {
        case let .revealing(session, currentID):
            setHover(
                assetID: assetID,
                currentID: currentID,
                session: session,
                isRevealing: true
            )
        case let .open(session, currentID):
            setHover(
                assetID: assetID,
                currentID: currentID,
                session: session,
                isRevealing: false
            )
        case .idle, .dismissing:
            break
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
}

extension FanPickerController {
    func commitSelection() {
        switch state {
        case let .revealing(session, _), let .open(session, _):
            settleTask?.cancel()
            settleTask = nil
            session.frozenAssets.forEach { $0.endImageFreeze() }
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
            activeAssets = session.frozenAssets
        case let .dismissing(session):
            activeAssets = session.reveal.frozenAssets
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
                .duration(itemCount: currentSession.revealItemCount)
            initialRevealElapsed = min(
                max(now.timeIntervalSince(currentSession.startDate), 0),
                revealDuration
            )
        case let .open(currentSession, currentID):
            session = currentSession
            highlightedID = currentID
            revealDuration = RevealMotionTimeline(configuration: configuration)
                .duration(itemCount: currentSession.revealItemCount)
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
            .dismissalDuration(itemCount: session.revealItemCount)
        settleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(dismissalDuration))
            guard !Task.isCancelled else { return }
            self?.finishDismissal(sessionID: session.id)
        }
    }
}

private extension FanPickerController {
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
        session.reveal.frozenAssets.forEach { $0.endImageFreeze() }
        state = .idle
        settleTask = nil
    }

    private func setHover(
        assetID: String?,
        currentID: String?,
        session: RevealSession,
        isRevealing: Bool
    ) {
        let nextID = session.assets.contains { $0.id == assetID }
            ? assetID
            : nil
        guard nextID != currentID else { return }
        state = isRevealing
            ? .revealing(session, highlightedID: nextID)
            : .open(session, highlightedID: nextID)
        if nextID != nil {
            hoverFeedbackToken += 1
        }
    }

}
#endif
