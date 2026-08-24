import CoreGraphics

/// Sizes and timing values used by FanPicker.
public struct FanPickerConfiguration: Sendable {
    /// Maximum number of recent photos shown.
    public var itemCount: Int

    /// Seconds before a hold opens the picker.
    public var holdDuration: Double
    /// Maximum finger movement, in points, allowed before the hold fails.
    public var maximumHoldMovement: CGFloat

    /// Side length of each recent-photo thumbnail, in points.
    public var recentSize: CGFloat
    /// Space between recent-photo thumbnails, in points.
    public var recentSpacing: CGFloat
    /// Corner radius of recent-photo thumbnails, in points.
    public var recentCornerRadius: CGFloat
    /// Vertical gap between the photo row and the trigger, in points.
    public var rowToControlGap: CGFloat

    /// Delay between consecutive thumbnail launches, in seconds.
    public var revealItemStagger: Double
    /// Duration of one thumbnail's reveal, in seconds.
    public var revealDuration: Double
    /// Height of the reveal path above the final row, in points.
    public var revealApex: CGFloat
    /// Thumbnail scale at the start of the reveal.
    public var revealInitialScale: CGFloat
    /// Largest thumbnail scale during the reveal.
    public var revealPeakScale: CGFloat
    /// Spring bounce used when thumbnails settle.
    public var revealSettleBounce: Double
    /// Duration of the closing animation, in seconds.
    public var dismissalDuration: Double

    /// Scale applied to the photo under the finger.
    public var hoverScale: CGFloat
    /// Extra hit area around each photo, in points.
    public var hoverHitExpansion: CGFloat
    /// Extra hit area that keeps the current photo selected, in points.
    public var hoverStickyExpansion: CGFloat

    /// Blur radius for app content while the picker is open.
    public var composerBlurRadius: CGFloat
    /// Opacity for app content while the picker is open.
    public var composerBlurOpacity: CGFloat

    /// Duration of the non-selected photo fade, in seconds.
    public var nonSelectedFadeDuration: Double

    /// Side length of a destination attachment, in points.
    public var attachmentSize: CGFloat
    /// Space between destination attachments, in points.
    public var attachmentSpacing: CGFloat
    /// Corner radius of destination attachments, in points.
    public var attachmentCornerRadius: CGFloat

    /// Duration of the selected-photo flight, in seconds.
    public var flightDuration: Double
    /// Spring bounce used by the selected-photo flight.
    public var flightBounce: Double

    /// Suggested side length for an attachment close badge, in points.
    public var closeBadgeSize: CGFloat
    /// Preview loading and network policy.
    public var imagePolicy: RecentPhotoImagePolicy

    /// Creates a configuration. Default values match ``reference``.
    public init(
        itemCount: Int = 4,
        holdDuration: Double = 0.14,
        maximumHoldMovement: CGFloat = 10,
        recentSize: CGFloat = 80,
        recentSpacing: CGFloat = 10,
        recentCornerRadius: CGFloat = 14,
        rowToControlGap: CGFloat = 8,
        revealItemStagger: Double = 0.018,
        revealDuration: Double = 0.38,
        revealApex: CGFloat = 32,
        revealInitialScale: CGFloat = 0.42,
        revealPeakScale: CGFloat = 1.018,
        revealSettleBounce: Double = 0.10,
        dismissalDuration: Double = 0.21,
        hoverScale: CGFloat = 1.08,
        hoverHitExpansion: CGFloat = 5,
        hoverStickyExpansion: CGFloat = 10,
        composerBlurRadius: CGFloat = 7,
        composerBlurOpacity: CGFloat = 0.42,
        nonSelectedFadeDuration: Double = 0.10,
        attachmentSize: CGFloat = 112,
        attachmentSpacing: CGFloat = 8,
        attachmentCornerRadius: CGFloat = 16,
        flightDuration: Double = 0.22,
        flightBounce: Double = 0.10,
        closeBadgeSize: CGFloat = 21,
        imagePolicy: RecentPhotoImagePolicy = .production
    ) {
        self.itemCount = itemCount
        self.holdDuration = holdDuration
        self.maximumHoldMovement = maximumHoldMovement
        self.recentSize = recentSize
        self.recentSpacing = recentSpacing
        self.recentCornerRadius = recentCornerRadius
        self.rowToControlGap = rowToControlGap
        self.revealItemStagger = revealItemStagger
        self.revealDuration = revealDuration
        self.revealApex = revealApex
        self.revealInitialScale = revealInitialScale
        self.revealPeakScale = revealPeakScale
        self.revealSettleBounce = revealSettleBounce
        self.dismissalDuration = dismissalDuration
        self.hoverScale = hoverScale
        self.hoverHitExpansion = hoverHitExpansion
        self.hoverStickyExpansion = hoverStickyExpansion
        self.composerBlurRadius = composerBlurRadius
        self.composerBlurOpacity = composerBlurOpacity
        self.nonSelectedFadeDuration = nonSelectedFadeDuration
        self.attachmentSize = attachmentSize
        self.attachmentSpacing = attachmentSpacing
        self.attachmentCornerRadius = attachmentCornerRadius
        self.flightDuration = flightDuration
        self.flightBounce = flightBounce
        self.closeBadgeSize = closeBadgeSize
        self.imagePolicy = imagePolicy
    }

    /// Values tuned for the reference interaction.
    public static let reference = FanPickerConfiguration()
}
