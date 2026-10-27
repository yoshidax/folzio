import AppKit
import FolzioCore
import FolzioLocalization
import QuartzCore
import os

@MainActor
final class PreviewViewController: NSViewController {
    private let model: BrowserModel
    private let decoder: any ImageDecoding
    private let archiveReader: any ArchiveReading
    private let imageView = ImagePreviewView()
    private let videoView = VideoPreviewView()
    private let containerView = NSView()
    private let contentHostView = NSView()
    private let transitionOverlay = SlideshowTransitionOverlayView()
    private var transitionState = SlideshowTransitionState()
    private var lastContainerSize: CGSize?
    private let transitionSignposter = OSSignposter(
        subsystem: "local.folzio.Folzio", category: "Performance"
    )
    private var animatedTask: Task<Void, Never>?
    private var configuredVideoURL: URL?
    /// Zoom level for the displayed image (FR-137). Neither persisted nor recorded in history.
    private var zoomTracker = PreviewZoomTracker()
    private var lastZoomAvailability: PreviewZoomAvailability?

    /// Temporary slideshow appearance independent of pane visibility.
    func setSlideshowBackground(_ enabled: Bool) {
        loadViewIfNeeded()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let color = enabled ? NSColor.black.cgColor : nil
        containerView.layer?.backgroundColor = color
        contentHostView.layer?.backgroundColor = color
        // Make status text and the spinner readable on the black background even in light appearance.
        imageView.appearance = enabled ? NSAppearance(named: .darkAqua) : nil
        CATransaction.commit()
    }

    var paneLayout: PaneLayout = .all {
        didSet {
            guard oldValue != paneLayout else { return }
            updateFromModel()
        }
    }

    var isPaneVisible = true {
        didSet {
            guard oldValue != isPaneVisible else { return }
            updateFromModel()
            notifyZoomAvailabilityIfChanged()
        }
    }

    /// Notifies when zoom in, zoom out, or Zoom to Fit availability changes (FR-134, FR-136).
    var onZoomAvailabilityChange: (() -> Void)?

    var zoomAvailability: PreviewZoomAvailability {
        PreviewZoomAvailability(
            isImageDisplayed: imageView.isShowingImage,
            isPreviewVisible: isPaneVisible,
            level: zoomTracker.level
        )
    }

    init(model: BrowserModel, decoder: any ImageDecoding, archiveReader: any ArchiveReading) {
        self.model = model
        self.decoder = decoder
        self.archiveReader = archiveReader
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    var primaryFocusView: NSView {
        if case .video = model.preview, !videoView.isHidden {
            return videoView
        }
        return imageView
    }

    var onDoubleClick: (() -> Void)? {
        get { imageView.onDoubleClick }
        set { imageView.onDoubleClick = newValue }
    }

    func togglePlayback() {
        guard !videoView.isHidden else { return }
        videoView.togglePlayPause()
    }

    @discardableResult
    func seekVideo(by seconds: Double) -> Bool {
        guard case .video = model.preview else { return false }
        videoView.seek(by: seconds)
        return true
    }

    // MARK: - Zoom (FR-133–FR-138)

    @discardableResult
    func zoomIn() -> Bool {
        guard zoomAvailability.canZoomIn else { return false }
        return applyZoomChange(zoomTracker.zoomIn())
    }

    @discardableResult
    func zoomOut() -> Bool {
        guard zoomAvailability.canZoomOut else { return false }
        return applyZoomChange(zoomTracker.zoomOut())
    }

    @discardableResult
    func zoomToFit() -> Bool {
        guard zoomAvailability.canFit else { return false }
        imageView.resetScrollPosition()
        return applyZoomChange(zoomTracker.fit())
    }

    /// Resets to 100% after history navigation even for the same image (FR-137). Does not announce.
    func resetZoom() {
        imageView.resetScrollPosition()
        guard zoomTracker.reset() else { return }
        applyCurrentZoom(announce: false)
        notifyZoomAvailabilityIfChanged()
    }

    private func applyZoomChange(_ changed: Bool) -> Bool {
        guard changed else { return false }
        applyCurrentZoom(announce: true)
        notifyZoomAvailabilityIfChanged()
        return true
    }

    private func applyCurrentZoom(announce: Bool) {
        let state = transitionSignposter.beginInterval("PreviewZoomApply")
        imageView.applyZoom(zoomTracker.level, announce: announce)
        transitionSignposter.endInterval("PreviewZoomApply", state)
    }

    private func notifyZoomAvailabilityIfChanged() {
        let availability = zoomAvailability
        guard availability != lastZoomAvailability else { return }
        lastZoomAvailability = availability
        onZoomAvailabilityChange?()
    }

    /// Identity of the displayed content. Uses the selected URL for `.image`, which carries no URL.
    private func zoomIdentity(for content: PreviewContent) -> URL? {
        switch content {
        case .image:
            model.selection.focused
        case let .loading(url), let .animatedImage(url), let .animatedImageData(url, _):
            url
        case .empty, .video, .unavailable:
            nil
        }
    }

    override func loadView() {
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.onDisplayedImageChange = { [weak self] in
            self?.notifyZoomAvailabilityIfChanged()
        }
        videoView.translatesAutoresizingMaskIntoConstraints = false
        videoView.isHidden = true

        containerView.wantsLayer = true
        containerView.layer?.masksToBounds = true
        contentHostView.wantsLayer = true
        contentHostView.translatesAutoresizingMaskIntoConstraints = false
        transitionOverlay.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(contentHostView)
        containerView.addSubview(transitionOverlay)
        contentHostView.addSubview(imageView)
        contentHostView.addSubview(videoView)

        for child in [contentHostView, transitionOverlay] {
            NSLayoutConstraint.activate([
                child.topAnchor.constraint(equalTo: containerView.topAnchor),
                child.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                child.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                child.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            ])
        }
        for child in [imageView, videoView] {
            NSLayoutConstraint.activate([
                child.topAnchor.constraint(equalTo: contentHostView.topAnchor),
                child.leadingAnchor.constraint(equalTo: contentHostView.leadingAnchor),
                child.trailingAnchor.constraint(equalTo: contentHostView.trailingAnchor),
                child.bottomAnchor.constraint(equalTo: contentHostView.bottomAnchor),
            ])
        }

        view = containerView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(
            self, selector: #selector(displayLanguageDidChange), name: .displayLanguageDidChange, object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidChangeScreen(_:)),
            name: NSWindow.didChangeScreenNotification,
            object: nil
        )
        updateFromModel()
        observePreview()
        observeListingForEmptyPreview()
    }

    @objc private func displayLanguageDidChange() {
        imageView.refreshLocalizedAccessibility()
        switch model.preview {
        case .empty, .loading, .unavailable:
            updateFromModel()
        case .image, .animatedImage, .animatedImageData, .video:
            break
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        updateScreenMaxPixel()
    }

    private func observePreview() {
        withObservationTracking {
            _ = model.preview
            _ = model.selection.focused
            _ = model.stopPlaybackSignal
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateFromModel()
                self?.observePreview()
            }
        }
    }

    private func observeListingForEmptyPreview() {
        withObservationTracking {
            _ = model.listing
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if case .empty = self.model.preview { self.updateFromModel() }
                self.observeListingForEmptyPreview()
            }
        }
    }

    private func updateFromModel() {
        // Reset to 100% only when switching to another image. Apply before display so the previous zoom is not briefly
        // drawn.
        if zoomTracker.present(zoomIdentity(for: model.preview)) {
            imageView.resetScrollPosition()
            applyCurrentZoom(announce: false)
        }
        defer { notifyZoomAvailabilityIfChanged() }

        switch model.preview {
        case .empty:
            animatedTask?.cancel()
            animatedTask = nil
            stopVideo()
            showImageView()
            if paneLayout.showsNoMediaMessage(in: model.listing) {
                imageView.showMessage(l10n.text(.previewNoMedia))
            } else {
                imageView.showEmpty()
            }
        case let .loading(url):
            animatedTask?.cancel()
            animatedTask = nil
            stopVideo()
            showImageView()
            imageView.showLoading(fileName: url.lastPathComponent)
        case let .image(decoded):
            animatedTask?.cancel()
            animatedTask = nil
            stopVideo()
            showImageView()
            imageView.showImage(
                decoded,
                fileName: model.selection.focused?.lastPathComponent ?? ""
            )
        case let .animatedImage(url):
            stopVideo()
            showImageView()
            loadAnimatedImage(url)
        case let .animatedImageData(url, data):
            stopVideo()
            showImageView()
            loadAnimatedImageData(url, data)
        case let .video(url):
            animatedTask?.cancel()
            animatedTask = nil
            guard isPaneVisible else {
                stopVideo()
                showImageView()
                imageView.showEmpty()
                cancelTransition()
                return
            }
            imageView.showEmpty()
            showVideoView()
            showVideo(url)
        case let .unavailable(name, reason):
            animatedTask?.cancel()
            animatedTask = nil
            stopVideo()
            showImageView()
            imageView.showUnavailable(name: name, reason: l10n.text(for: reason))
        }
        applyTransitionAction(transitionState.reduce(.displayed(content: model.preview, focused: model.selection.focused)))
    }

    /// Passes a video URL to playback. Ignores setting the same URL again.
    private func showVideo(_ url: URL) {
        guard configuredVideoURL != url else { return }
        configuredVideoURL = url
        let generation = transitionState.generation
        videoView.onReadyForTransition = { [weak self] in
            self?.transitionReady(url: url, generation: generation)
        }
        let playback = model.playbackRequest
        if ArchiveURL.parse(url) != nil {
            // Play videos inside a zip with an AVURLAsset created through ArchiveAssetFactory.
            videoView.configure(
                asset: ArchiveAssetFactory.makeAsset(for: url, reader: archiveReader),
                autoplay: playback.autoplay,
                loop: playback.loop,
                fileName: url.lastPathComponent
            )
        } else {
            videoView.configure(
                url: url,
                autoplay: playback.autoplay,
                loop: playback.loop,
                fileName: url.lastPathComponent
            )
        }
    }

    private func showImageView() {
        imageView.isHidden = false
        videoView.isHidden = true
    }

    private func showVideoView() {
        imageView.isHidden = true
        videoView.isHidden = false
    }

    private func stopVideo() {
        videoView.stop()
        videoView.isHidden = true
        configuredVideoURL = nil
    }

    private func loadAnimatedImage(_ url: URL) {
        animatedTask?.cancel()
        imageView.showLoading(fileName: url.lastPathComponent)

        let maxPixelSize = max(1, model.screenMaxPixel)
        let generation = transitionState.generation
        animatedTask = Task { [weak self] in
            guard let self else { return }

            let fallback: DecodedImage?
            do {
                fallback = try await self.decoder.decode(url, maxPixelSize: maxPixelSize)
            } catch {
                fallback = nil
            }

            guard !Task.isCancelled else { return }
            guard case let .animatedImage(current) = self.model.preview, current == url else {
                return
            }
            self.imageView.showAnimated(
                url: url,
                fileName: url.lastPathComponent,
                fallback: fallback
            )
            self.transitionReady(url: url, generation: generation)
        }
    }

    private func loadAnimatedImageData(_ url: URL, _ data: Data) {
        animatedTask?.cancel()
        imageView.showLoading(fileName: url.lastPathComponent)

        let maxPixelSize = max(1, model.screenMaxPixel)
        let generation = transitionState.generation
        animatedTask = Task { [weak self] in
            guard let self else { return }

            let fallback: DecodedImage?
            do {
                fallback = try await self.decoder.decode(data: data, maxPixelSize: maxPixelSize)
            } catch {
                fallback = nil
            }

            guard !Task.isCancelled else { return }
            guard case let .animatedImageData(current, _) = self.model.preview, current == url else {
                return
            }
            self.imageView.showAnimated(
                source: .data(data),
                fileName: url.lastPathComponent,
                fallback: fallback
            )
            self.transitionReady(url: url, generation: generation)
        }
    }

    func beginTransition(to url: URL, current: URL?, effect: SlideshowTransitionEffect) {
        view.layoutSubtreeIfNeeded()
        applyTransitionAction(transitionState.reduce(.arm(target: url, current: current, effect: effect)))
    }

    func cancelTransition() {
        applyTransitionAction(transitionState.reduce(.cancel))
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let size = containerView.bounds.size
        if let lastContainerSize, lastContainerSize != size {
            applyTransitionAction(transitionState.reduce(.containerResized))
        }
        lastContainerSize = size
    }

    private func transitionReady(url: URL, generation: Int) {
        applyTransitionAction(transitionState.reduce(.ready(url: url, generation: generation)))
    }

    private func clearTransitionLayers() {
        transitionOverlay.layer?.removeAllAnimations()
        contentHostView.layer?.removeAllAnimations()
        transitionOverlay.clear()
    }

    private func applyTransitionAction(_ action: SlideshowTransitionState.Action) {
        switch action {
        case .none:
            break
        case .hold(let replacing):
            if replacing {
                clearTransitionLayers()
                transitionSignposter.emitEvent("SlideshowTransitionCancel")
            }
            if !videoView.isHidden {
                let snapshot = videoView.freezeForTransition()
                transitionOverlay.show(image: snapshot.image,
                    frame: videoView.convert(snapshot.videoRect, to: containerView), gravity: .resizeAspect)
            } else {
                let snapshot = imageView.transitionSnapshot()
                transitionOverlay.show(image: snapshot.image,
                    frame: imageView.convert(snapshot.frame, to: containerView), gravity: snapshot.gravity)
            }
        case let .animate(effect, generation):
            startTransitionAnimation(effect: effect, generation: generation)
        case .remove(let completed):
            clearTransitionLayers()
            if completed {
                transitionSignposter.emitEvent("SlideshowTransitionEnd")
            } else {
                transitionSignposter.emitEvent("SlideshowTransitionCancel")
            }
        }
    }

    private func startTransitionAnimation(effect: SlideshowTransitionEffect, generation: Int) {
        guard let previous = transitionOverlay.layer, let next = contentHostView.layer else {
            cancelTransition()
            return
        }
        transitionSignposter.emitEvent("SlideshowTransitionStart")
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.applyTransitionAction(self.transitionState.reduce(.completed(generation: generation)))
            }
        }
        func add(_ layer: CALayer, _ keyPath: String, from: Any, to: Any) {
            let animation = CABasicAnimation(keyPath: keyPath)
            animation.fromValue = from
            animation.toValue = to
            animation.duration = 0.5
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
            layer.add(animation, forKey: "slideshow." + keyPath)
        }
        switch effect {
        case .none:
            break
        case .crossfade:
            add(previous, "opacity", from: 1, to: 0)
            add(next, "opacity", from: 0, to: 1)
        case .slide:
            add(previous, "transform.translation.x", from: 0, to: -containerView.bounds.width)
            add(next, "transform.translation.x", from: containerView.bounds.width, to: 0)
        case .zoom:
            add(previous, "opacity", from: 1, to: 0)
            add(next, "opacity", from: 0, to: 1)
            let center = CGPoint(x: next.bounds.midX, y: next.bounds.midY)
            var transform = CATransform3DMakeTranslation(center.x, center.y, 0)
            transform = CATransform3DScale(transform, 0.6, 0.6, 1)
            transform = CATransform3DTranslate(transform, -center.x, -center.y, 0)
            add(next, "transform", from: NSValue(caTransform3D: transform), to: NSValue(caTransform3D: CATransform3DIdentity))
        }
        CATransaction.commit()
    }

    private func updateScreenMaxPixel() {
        guard let screen = view.window?.screen ?? NSScreen.main else { return }
        let frame = screen.frame.size
        let pixels = Int(max(frame.width, frame.height) * screen.backingScaleFactor)
        guard pixels > 0, pixels != model.screenMaxPixel else { return }
        model.screenMaxPixel = pixels
    }

    @objc private func windowDidChangeScreen(_ notification: Notification) {
        guard let window = view.window,
              let changedWindow = notification.object as? NSWindow,
              changedWindow === window else {
            return
        }
        updateScreenMaxPixel()
    }
}
