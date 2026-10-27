import Foundation

/// Arbitrates only the preview display. Does not hold deadlines, selections, or snapshot images.
public struct SlideshowTransitionState: Sendable, Equatable {
    public enum Phase: Sendable, Equatable { case idle, holding, animating }
    public enum Readiness: Sendable, Equatable { case ready, pending }
    public enum Event {
        case arm(target: URL, current: URL?, effect: SlideshowTransitionEffect)
        case displayed(content: PreviewContent, focused: URL?)
        // Compare generations so an old notification cannot start a new effect when the same URL is prepared again.
        case ready(url: URL, generation: Int)
        case completed(generation: Int)
        case cancel
        case containerResized
    }
    public enum Action: Sendable, Equatable {
        case none
        case hold(replacing: Bool)
        case animate(effect: SlideshowTransitionEffect, generation: Int)
        case remove(completed: Bool)
    }

    public private(set) var phase: Phase = .idle
    public private(set) var targetURL: URL?
    public private(set) var effect: SlideshowTransitionEffect = .none
    public private(set) var generation = 0

    public init() {}

    public static func readiness(of content: PreviewContent) -> Readiness {
        switch content {
        case .image, .unavailable, .empty: .ready
        case .loading, .animatedImage, .animatedImageData, .video: .pending
        }
    }

    public mutating func reduce(_ event: Event) -> Action {
        switch event {
        case let .arm(target, current, effect):
            guard target != current, effect != .none else { return remove(completed: false) }
            let replacing = phase != .idle
            generation &+= 1
            targetURL = target
            self.effect = effect
            phase = .holding
            return .hold(replacing: replacing)
        case let .displayed(content, focused):
            guard phase != .idle else { return .none }
            let url: URL?
            switch content {
            case let .loading(value), let .animatedImage(value), let .animatedImageData(value, _), let .video(value):
                url = value
            case .image, .unavailable, .empty:
                url = focused
            }
            guard url == targetURL else { return remove(completed: false) }
            guard phase == .holding, Self.readiness(of: content) == .ready else { return .none }
            return animate()
        case let .ready(url, generation):
            guard phase == .holding, url == targetURL, generation == self.generation else { return .none }
            return animate()
        case let .completed(generation):
            guard phase == .animating, generation == self.generation else { return .none }
            return remove(completed: true)
        case .cancel, .containerResized:
            return remove(completed: false)
        }
    }

    private mutating func animate() -> Action {
        phase = .animating
        return .animate(effect: effect, generation: generation)
    }

    private mutating func remove(completed: Bool) -> Action {
        guard phase != .idle else { return .none }
        generation &+= 1
        phase = .idle
        targetURL = nil
        effect = .none
        return .remove(completed: completed)
    }
}
