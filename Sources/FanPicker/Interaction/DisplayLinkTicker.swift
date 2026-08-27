#if canImport(UIKit)
import Foundation
import QuartzCore

@MainActor
final class DisplayLinkTicker {
    @MainActor
    private final class Proxy: NSObject {
        weak var ticker: DisplayLinkTicker?

        @objc func step(_ link: CADisplayLink) {
            guard let ticker else {
                link.invalidate()
                return
            }
            ticker.onTick?(link)
        }
    }

    private var link: CADisplayLink?
    private var onTick: (@MainActor (CADisplayLink) -> Void)?

    var isRunning: Bool { link != nil }

    func start(_ onTick: @escaping @MainActor (CADisplayLink) -> Void) {
        stop()
        self.onTick = onTick

        // CADisplayLink retains its target, so the proxy must not retain us.
        let proxy = Proxy()
        proxy.ticker = self
        let link = CADisplayLink(
            target: proxy,
            selector: #selector(Proxy.step(_:))
        )
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        onTick = nil
    }
}
#endif
