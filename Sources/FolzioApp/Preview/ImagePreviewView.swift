import AppKit
import ImageIO
import FolzioCore
import FolzioLocalization

enum AnimatedSource: Sendable {
    case url(URL)
    case data(Data)
}

@MainActor
final class ImagePreviewView: NSView {
    @MainActor
    fileprivate final class AnimationState: @unchecked Sendable {
        weak var view: ImagePreviewView?
        var shouldStop = false
        var frameCount = 0

        init(view: ImagePreviewView) {
            self.view = view
        }

        func receive(_ image: CGImage, stop: UnsafeMutablePointer<Bool>) {
            if shouldStop {
                stop.pointee = true
                return
            }
            guard let view, view.isCurrentAnimation(self) else {
                stop.pointee = true
                return
            }
            frameCount += 1
            view.displayFrame(image)
        }
    }

    private let contentLayer = CALayer()
    private let messageStack = NSStackView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private let spinner = NSProgressIndicator()
    // NSScroller determines its orientation from the initial frame, so create it already wide or tall.
    private let horizontalScroller = NSScroller(frame: NSRect(x: 0, y: 0, width: 100, height: 15))
    private let verticalScroller = NSScroller(frame: NSRect(x: 0, y: 0, width: 15, height: 100))
    private var scrollCenter = CGPoint(x: 0.5, y: 0.5)
    private var scrollLayout = PreviewScrollLayout(imageSize: .zero, viewport: .zero, center: .zero)
    var interactionMode: PreviewInteractionMode = .wheelZoomPan {
        didSet {
            guard oldValue != interactionMode else { return }
            endDrag()
            pinchAnchor = nil
            scrollInput.reset()
            contentLayer.removeAnimation(forKey: "wheelZoom")
            stopKeyboardScrolling()
            needsLayout = true
        }
    }
    var onZoomFactor: ((Double, CGPoint, Bool) -> Void)?
    private var dragStart: CGPoint?
    private var dragLast: CGPoint?
    private var isDraggingImage = false
    private var pinchAnchor: CGPoint?
    private var scrollInput = PreviewScrollInput()
    private var keyboardScroll = PreviewKeyboardScroll()
    private var keyboardScrollTimer: Timer?

    /// Called when whether an image is displayed changes (first frame or clearing the image).
    var onDisplayedImageChange: (() -> Void)?

    private var displayedImage: CGImage? {
        didSet {
            if displayedImage == nil {
                endDrag()
                pinchAnchor = nil
                scrollInput.reset()
                contentLayer.removeAnimation(forKey: "wheelZoom")
                stopKeyboardScrolling()
                horizontalScroller.isHidden = true
                verticalScroller.isHidden = true
            }
            guard (oldValue == nil) != (displayedImage == nil) else { return }
            updateAccessibilityValue()
            onDisplayedImageChange?()
        }
    }
    /// Zoom level (FR-133). Applied only to the frame; does not touch contents or animation.
    private var zoom = PreviewZoom.fit

    var isShowingImage: Bool { displayedImage != nil }
    private var fallbackImage: CGImage?
    private var animatedSource: AnimatedSource?
    private var animationState: AnimationState?
    private var fileName = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var acceptsFirstResponder: Bool { true }

    private func setup() {
        wantsLayer = true
        layer = CALayer()
        // Clip outside the scroll area.
        layer?.masksToBounds = true

        contentLayer.contentsGravity = .resize
        contentLayer.magnificationFilter = .trilinear
        layer?.addSublayer(contentLayer)

        for scroller in [horizontalScroller, verticalScroller] {
            // A standalone overlay scroller has no fade control from NSScrollView and shows no knob. Layer the
            // standard always-visible style over the image.
            scroller.scrollerStyle = .legacy
            scroller.isEnabled = true
            scroller.target = self
            scroller.action = #selector(scrollbarChanged(_:))
            scroller.isHidden = true
            addSubview(scroller)
        }

        refreshLocalizedAccessibility()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        nameLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        nameLabel.alignment = .center
        nameLabel.maximumNumberOfLines = 2

        detailLabel.alignment = .center
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.preferredMaxLayoutWidth = 400

        messageStack.translatesAutoresizingMaskIntoConstraints = false
        messageStack.orientation = .vertical
        messageStack.alignment = .centerX
        messageStack.spacing = 8
        messageStack.addArrangedSubview(spinner)
        messageStack.addArrangedSubview(nameLabel)
        messageStack.addArrangedSubview(detailLabel)
        messageStack.isHidden = true
        addSubview(messageStack)

        NSLayoutConstraint.activate([
            messageStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            messageStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            messageStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            messageStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            messageStack.widthAnchor.constraint(lessThanOrEqualToConstant: 440),
        ])

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayOptionsDidChange(_:)),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowResignedKey(_:)), name: NSWindow.didResignKeyNotification, object: nil
        )
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard displayedImage != nil, !bounds.isEmpty else {
            contentLayer.frame = .zero
            horizontalScroller.isHidden = true
            verticalScroller.isHidden = true
            return
        }
        let size = fittedFrame().size
        scrollLayout = PreviewScrollLayout(imageSize: size, viewport: bounds.size, center: scrollCenter)
        scrollCenter = scrollLayout.center
        contentLayer.frame = scrollLayout.frame
        contentLayer.contentsScale = backingScale
        updateScrollbars()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        contentLayer.removeAnimation(forKey: "wheelZoom")
        needsLayout = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        if newSize != frame.size { contentLayer.removeAnimation(forKey: "wheelZoom") }
        super.setFrameSize(newSize)
    }

    /// Applies the zoom level. Set `announce` only for changes from explicit actions to announce the new level
    /// (FR-138).
    func applyZoom(_ zoom: PreviewZoom, announce: Bool, anchor: CGPoint? = nil, animateWheel: Bool = false) {
        let changed = zoom != self.zoom
        let previousLayout = scrollLayout
        let displayedLayer = contentLayer.presentation() ?? contentLayer
        let previousPosition = displayedLayer.position
        let previousBounds = displayedLayer.bounds
        if !animateWheel { contentLayer.removeAnimation(forKey: "wheelZoom") }
        self.zoom = zoom
        updateAccessibilityValue()
        if changed {
            if let anchor {
                scrollCenter = previousLayout.resized(imageSize: fittedFrame().size, viewport: bounds.size, anchoredAt: anchor).center
            }
            needsLayout = true
            layoutSubtreeIfNeeded()
            if animateWheel, isShowingImage, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                let position = CABasicAnimation(keyPath: "position")
                position.fromValue = NSValue(point: previousPosition)
                position.toValue = NSValue(point: contentLayer.position)
                let bounds = CABasicAnimation(keyPath: "bounds")
                bounds.fromValue = NSValue(rect: previousBounds)
                bounds.toValue = NSValue(rect: contentLayer.bounds)
                let animation = CAAnimationGroup()
                animation.animations = [position, bounds]
                animation.duration = 0.12
                animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
                contentLayer.add(animation, forKey: "wheelZoom")
            }
        }
        guard announce, changed, isShowingImage else { return }
        NSAccessibility.post(
            element: self,
            notification: .announcementRequested,
            userInfo: [
                .announcement: Self.percentText(zoom),
                .priority: NSAccessibilityPriorityLevel.medium.rawValue,
            ]
        )
    }

    func resetScrollPosition() {
        endDrag()
        pinchAnchor = nil
        scrollInput.reset()
        stopKeyboardScrolling()
        contentLayer.removeAnimation(forKey: "wheelZoom")
        scrollCenter = CGPoint(x: 0.5, y: 0.5)
        needsLayout = true
    }

    private func updateScrollbars() {
        let thickness = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
        let horizontal = scrollLayout.horizontal
        let vertical = scrollLayout.vertical
        horizontalScroller.isHidden = interactionMode != .scroll || !horizontal
        verticalScroller.isHidden = interactionMode != .scroll || !vertical
        horizontalScroller.frame = CGRect(x: 0, y: 0, width: max(0, bounds.width - (vertical ? thickness : 0)), height: thickness)
        verticalScroller.frame = CGRect(x: max(0, bounds.width - thickness), y: horizontal ? thickness : 0, width: thickness, height: max(0, bounds.height - (horizontal ? thickness : 0)))
        if horizontal {
            let overflow = scrollLayout.frame.width - bounds.width
            horizontalScroller.knobProportion = bounds.width / scrollLayout.frame.width
            horizontalScroller.doubleValue = Double(-scrollLayout.frame.minX / overflow)
        }
        if vertical {
            let overflow = scrollLayout.frame.height - bounds.height
            verticalScroller.knobProportion = bounds.height / scrollLayout.frame.height
            verticalScroller.doubleValue = Double(1 + scrollLayout.frame.minY / overflow)
        }
    }

    private func moveScroll(x: CGFloat, y: CGFloat) {
        guard isShowingImage, scrollLayout.frame.width > 0, scrollLayout.frame.height > 0 else { return }
        contentLayer.removeAnimation(forKey: "wheelZoom")
        scrollCenter = scrollLayout.moved(x: x, y: y, viewport: bounds.size).center
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    override func scrollWheel(with event: NSEvent) {
        if interactionMode == .wheelZoomPan, isShowingImage {
            let phase: PreviewScrollInput.Phase
            if event.phase.contains(.mayBegin) { phase = .mayBegin }
            else if event.phase.contains(.began) { phase = .began }
            else if event.phase.contains(.changed) { phase = .changed }
            else if event.phase.contains(.ended) { phase = .ended }
            else if event.phase.contains(.cancelled) { phase = .cancelled }
            else { phase = .none }
            let action = scrollInput.classify(phase: phase, isMomentum: !event.momentumPhase.isEmpty)
            switch action {
            case .pan:
                moveScroll(x: -event.scrollingDeltaX, y: event.scrollingDeltaY)
            case .zoom where event.scrollingDeltaY != 0:
                let point = convert(event.locationInWindow, from: nil)
                let amount = Double(event.scrollingDeltaY) / (event.hasPreciseScrollingDeltas ? 40 : 1)
                onZoomFactor?(pow(1.1, amount), point, true)
            case .zoom, .ignore:
                break
            }
            return
        }
        guard isShowingImage, scrollLayout.horizontal || scrollLayout.vertical else {
            super.scrollWheel(with: event)
            return
        }
        // NSEvent deltas already reflect the OS scroll direction setting.
        // This view uses a bottom-left origin, so the sign differs between horizontal and vertical image coordinates.
        moveScroll(x: -event.scrollingDeltaX, y: event.scrollingDeltaY)
    }

    override func magnify(with event: NSEvent) {
        guard interactionMode == .wheelZoomPan, isShowingImage else {
            super.magnify(with: event)
            return
        }
        if pinchAnchor == nil {
            pinchAnchor = convert(event.locationInWindow, from: nil)
        }
        if let anchor = pinchAnchor, event.magnification != 0 {
            onZoomFactor?(PreviewZoom.pinchFactor(for: Double(event.magnification)), anchor, false)
        }
        if event.phase == .ended || event.phase == .cancelled {
            pinchAnchor = nil
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard interactionMode == .wheelZoomPan, isShowingImage, event.clickCount == 1 else {
            super.mouseDown(with: event)
            return
        }
        dragStart = convert(event.locationInWindow, from: nil)
        dragLast = dragStart
        window?.makeFirstResponder(self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, let last = dragLast else { super.mouseDragged(with: event); return }
        let point = convert(event.locationInWindow, from: nil)
        if !isDraggingImage, hypot(point.x - start.x, point.y - start.y) >= 4 {
            isDraggingImage = true
            NSCursor.closedHand.push()
        }
        if isDraggingImage {
            moveScroll(x: -(point.x - last.x), y: -(point.y - last.y))
            dragLast = point
        }
    }

    override func mouseUp(with event: NSEvent) {
        if dragStart != nil { endDrag(); return }
        super.mouseUp(with: event)
    }

    @objc private func windowResignedKey(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        endDrag()
        pinchAnchor = nil
        scrollInput.reset()
        stopKeyboardScrolling()
    }

    private func endDrag() {
        if isDraggingImage { NSCursor.pop() }
        isDraggingImage = false
        dragStart = nil
        dragLast = nil
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { stopKeyboardScrolling() }
        return resigned
    }

    override func viewDidHide() {
        super.viewDidHide()
        endDrag()
        stopKeyboardScrolling()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            endDrag()
            stopKeyboardScrolling()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    private func keyboardDirection(for event: NSEvent) -> PreviewKeyboardScroll.Direction? {
        switch event.specialKey {
        case .leftArrow: .left
        case .rightArrow: .right
        case .upArrow: .up
        case .downArrow: .down
        default: nil
        }
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.option, .command, .control, .shift])
        if modifiers == .option, isShowingImage, let direction = keyboardDirection(for: event) {
            if !keyboardScroll.contains(direction) {
                keyboardScroll.press(direction)
                repeatKeyboardScroll()
                startKeyboardScrollTimerIfNeeded()
            }
            return
        }
        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        if let direction = keyboardDirection(for: event), keyboardScroll.contains(direction) {
            keyboardScroll.release(direction)
            if keyboardScroll.isEmpty { stopKeyboardScrolling() }
            return
        }
        super.keyUp(with: event)
    }

    override func flagsChanged(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.option, .command, .control, .shift])
        if modifiers != .option { stopKeyboardScrolling() }
        super.flagsChanged(with: event)
    }

    private func startKeyboardScrollTimerIfNeeded() {
        guard keyboardScrollTimer == nil else { return }
        let timer = Timer(timeInterval: max(0.01, NSEvent.keyRepeatInterval), target: self,
                          selector: #selector(repeatKeyboardScroll), userInfo: nil, repeats: true)
        timer.fireDate = Date(timeIntervalSinceNow: max(0.01, NSEvent.keyRepeatDelay))
        RunLoop.main.add(timer, forMode: .common)
        keyboardScrollTimer = timer
    }

    @objc func repeatKeyboardScroll() {
        let movement = keyboardScroll.movement(step: 40)
        if movement != .zero { moveScroll(x: movement.x, y: movement.y) }
    }

    private func stopKeyboardScrolling() {
        keyboardScrollTimer?.invalidate()
        keyboardScrollTimer = nil
        keyboardScroll.reset()
    }

    @objc private func scrollbarChanged(_ sender: NSScroller) {
        let horizontal = sender === horizontalScroller
        let image = horizontal ? scrollLayout.frame.width : scrollLayout.frame.height
        let viewport = horizontal ? bounds.width : bounds.height
        guard image > viewport else { return }
        let isVertical = !horizontal
        switch sender.hitPart {
        case .knob:
            let value = CGFloat(sender.doubleValue)
            let offset = (isVertical ? 1 - value : value) * (image - viewport)
            if horizontal { scrollCenter.x = (offset + viewport / 2) / image }
            else { scrollCenter.y = (offset + viewport / 2) / image }
            needsLayout = true
            layoutSubtreeIfNeeded()
        case .decrementLine, .decrementPage:
            let step: CGFloat = sender.hitPart == .decrementPage ? viewport * 0.8 : 40
            moveScroll(x: horizontal ? -step : 0, y: isVertical ? step : 0)
        case .incrementLine, .incrementPage:
            let step: CGFloat = sender.hitPart == .incrementPage ? viewport * 0.8 : 40
            moveScroll(x: horizontal ? step : 0, y: isVertical ? -step : 0)
        default: break
        }
    }

    private func updateAccessibilityValue() {
        // Do not expose the zoom level when there is no image (FR-138).
        setAccessibilityValue(isShowingImage ? Self.percentText(zoom) : nil)
    }

    func refreshLocalizedAccessibility() {
        updateAccessibilityValue()
        horizontalScroller.setAccessibilityLabel(l10n.text(.previewScrollHorizontal))
        verticalScroller.setAccessibilityLabel(l10n.text(.previewScrollVertical))
    }

    private static func percentText(_ zoom: PreviewZoom) -> String {
        l10n.percent(Int(zoom.percentage.rounded()))
    }

    func showImage(_ image: DecodedImage, fileName: String) {
        stopAnimation(clearAnimatedSource: true)
        self.fileName = fileName
        setAccessibilityLabel(fileName)
        messageStack.isHidden = true
        spinner.stopAnimation(nil)
        setDisplayed(image.cgImage)
    }

    func showAnimated(url: URL, fileName: String, fallback: DecodedImage?) {
        showAnimated(source: .url(url), fileName: fileName, fallback: fallback)
    }

    func showAnimated(source: AnimatedSource, fileName: String, fallback: DecodedImage?) {
        stopAnimation(clearAnimatedSource: false)
        self.fileName = fileName
        animatedSource = source
        fallbackImage = fallback?.cgImage
        setAccessibilityLabel(fileName)
        messageStack.isHidden = true
        spinner.stopAnimation(nil)

        if let fallback {
            setDisplayed(fallback.cgImage)
        } else {
            displayedImage = nil
            contentLayer.contents = nil
        }

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            if fallback == nil {
                showUnavailable(name: fileName, reason: l10n.text(.previewAnimationUnavailable))
            }
            return
        }

        startAnimation()
    }

    func showLoading(fileName: String) {
        stopAnimation(clearAnimatedSource: true)
        self.fileName = fileName
        setAccessibilityLabel(fileName)
        displayedImage = nil
        contentLayer.contents = nil

        spinner.isHidden = false
        spinner.startAnimation(nil)
        nameLabel.stringValue = l10n.text(.emptyLoading)
        detailLabel.stringValue = fileName
        messageStack.isHidden = false
    }

    func showEmpty() {
        stopAnimation(clearAnimatedSource: true)
        fileName = ""
        setAccessibilityLabel("")
        displayedImage = nil
        contentLayer.contents = nil
        spinner.stopAnimation(nil)
        messageStack.isHidden = true
    }

    func showUnavailable(name: String, reason: String) {
        stopAnimation(clearAnimatedSource: true)
        fileName = name
        setAccessibilityLabel(name)
        displayedImage = nil
        contentLayer.contents = nil

        spinner.stopAnimation(nil)
        spinner.isHidden = true
        nameLabel.stringValue = name
        detailLabel.stringValue = l10n.text(.previewUnavailable, .text(reason))
        messageStack.isHidden = false
    }

    func showMessage(_ text: String) {
        stopAnimation(clearAnimatedSource: true)
        setAccessibilityLabel(text)
        displayedImage = nil
        contentLayer.contents = nil

        spinner.stopAnimation(nil)
        spinner.isHidden = true
        nameLabel.stringValue = text
        detailLabel.stringValue = ""
        messageStack.isHidden = false
    }

    func transitionSnapshot() -> (image: CGImage?, frame: CGRect, gravity: CALayerContentsGravity) {
        layoutSubtreeIfNeeded()
        if let displayedImage {
            // Share the same image as contentLayer.contents and avoid decoding or redrawing it again.
            return (displayedImage, contentLayer.frame, contentLayer.contentsGravity)
        }
        guard !messageStack.isHidden, let layer else { return (nil, .zero, .resize) }
        displayIfNeeded()
        // Draw only the text and spinner area; do not create a bitmap for the entire large preview.
        let rect = messageStack.frame.integral
        let scale = backingScale
        guard rect.width > 0, rect.height > 0,
              let context = CGContext(data: nil, width: Int(rect.width * scale), height: Int(rect.height * scale),
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return (nil, .zero, .resize) }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -rect.minX, y: -rect.minY)
        layer.render(in: context)
        return (context.makeImage(), rect, .resize)
    }

    fileprivate func isCurrentAnimation(_ state: AnimationState) -> Bool {
        animationState === state
    }

    fileprivate func displayFrame(_ image: CGImage) {
        setDisplayed(image)
    }

    private func startAnimation() {
        guard let source = animatedSource else { return }

        let state = AnimationState(view: self)
        animationState = state

        let handler: CGImageSourceAnimationBlock = { _, image, stop in
            MainActor.assumeIsolated {
                state.receive(image, stop: stop)
            }
        }
        let status: OSStatus
        switch source {
        case let .url(url):
            status = CGAnimateImageAtURLWithBlock(url as CFURL, nil, handler)
        case let .data(data):
            status = CGAnimateImageDataWithBlock(data as CFData, nil, handler)
        }

        guard status == noErr else {
            animationState = nil
            if fallbackImage == nil {
                showUnavailable(name: fileName, reason: l10n.text(.previewAnimationUnavailable))
            }
            return
        }
    }

    private func stopAnimation(clearAnimatedSource: Bool) {
        animationState?.shouldStop = true
        animationState = nil
        spinner.stopAnimation(nil)
        if clearAnimatedSource {
            animatedSource = nil
            fallbackImage = nil
        }
    }

    private func setDisplayed(_ image: CGImage) {
        displayedImage = image
        contentLayer.contents = image
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    private var backingScale: CGFloat {
        window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    private func fittedFrame() -> CGRect {
        guard let image = displayedImage else { return .zero }

        let scale = backingScale
        let pixelContainer = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let fitted = FitCalculator.frame(
            imageSize: CGSize(width: image.width, height: image.height),
            in: pixelContainer,
            zoom: zoom
        )

        return CGRect(
            x: fitted.origin.x / scale,
            y: fitted.origin.y / scale,
            width: fitted.width / scale,
            height: fitted.height / scale
        )
    }

    @objc private func accessibilityDisplayOptionsDidChange(_ notification: Notification) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            contentLayer.removeAnimation(forKey: "wheelZoom")
        }
        guard animatedSource != nil else { return }

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            stopAnimation(clearAnimatedSource: false)
            if let fallbackImage {
                setDisplayed(fallbackImage)
            }
        } else if animationState == nil {
            startAnimation()
        }
    }
}
