import AssistantCore
import SwiftUI
import UIKit

@MainActor
final class ChatViewport: ObservableObject {
    @Published private(set) var nearBottom = true
    weak var controller: ChatScrollController?
    func jumpToLatest() { controller?.jumpToLatest() }
    func pinDisclosure(_ id: UUID) { controller?.pinDisclosure(id) }
    func updateNearBottom(_ value: Bool) { if nearBottom != value { nearBottom = value } }
}

/// Eager layout within the bounded message window avoids estimated lazy-row heights.
/// The reader's actual visible row and offset survive content and keyboard size changes.
struct StableChatScrollView<Content: View>: UIViewControllerRepresentable {
    let conversationID: UUID
    let isStreaming: Bool
    let hasMessages: Bool
    let composerFocused: Bool
    let dismissKeyboard: () -> Void
    let viewport: ChatViewport
    @ViewBuilder var content: () -> Content

    func makeUIViewController(context: Context) -> ChatScrollController {
        let controller = ChatScrollController(viewport: viewport)
        update(controller, context: context)
        return controller
    }
    func updateUIViewController(_ controller: ChatScrollController, context: Context) {
        update(controller, context: context)
    }
    private func update(_ controller: ChatScrollController, context: Context) {
        // A new hosting root owns its own navigation/accessibility graph. Copy only public
        // presentation values; cloning the whole environment also clones another root's AX state.
        let root = content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
            .environment(\.colorScheme, context.environment.colorScheme)
            .environment(\.dynamicTypeSize, context.environment.dynamicTypeSize)
            .environment(\.locale, context.environment.locale)
            .environment(\.layoutDirection, context.environment.layoutDirection)
            .disabled(!context.environment.isEnabled)
            .tint(Color.primary)
        controller.update(AnyView(root), conversationID: conversationID, streaming: isStreaming, hasMessages: hasMessages)
        controller.attach(viewport)
        controller.composerFocused = composerFocused
        controller.dismissKeyboard = dismissKeyboard
    }
    static func dismantleUIViewController(_ controller: ChatScrollController, coordinator: ()) { controller.detach() }
}

@MainActor
final class ChatScrollController: UIViewController, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    var composerFocused = false
    var dismissKeyboard: (() -> Void)?
    private let scroll = AnchoredChatScroll()
    private let host = UIHostingController(rootView: AnyView(EmptyView()))
    private weak var viewport: ChatViewport?
    private var conversationID: UUID?
    private var streaming = false
    private var hasMessages = false
    private var follow = ConversationFollow()
    private var displayLink: CADisplayLink?
    private var frameDriver: ChatFrameDriver?
    private var lastFrameTime: CFTimeInterval = 0
    private var pendingJump = true
    private var reconciling = false
    private var lastContentSize = CGSize.zero
    private var lastViewportSize = CGSize.zero
    private var anchor: (id: UUID, offset: CGFloat)?
    private var lastOffset: CGFloat = 0
    private var reachedBottomDuringGesture = false
    private var disclosureAnchor: (id: UUID, offset: CGFloat)?

    init(viewport: ChatViewport) { self.viewport = viewport; super.init(nibName: nil, bundle: nil); viewport.controller = self }
    required init?(coder: NSCoder) { fatalError("Use init(viewport:)") }
    override func loadView() {
        view = scroll
        scroll.delegate = self
        scroll.keyboardDismissMode = .interactive
        scroll.alwaysBounceVertical = true
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.backgroundColor = .systemBackground
        scroll.accessibilityIdentifier = "conversation-scroll"
        scroll.panGestureRecognizer.addTarget(self, action: #selector(readerPanned(_:)))
        addChild(host)
        host.sizingOptions = [.intrinsicContentSize]
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            host.view.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])
        host.didMove(toParent: self)
        scroll.didLayout = { [weak self] in self?.reconcileLayout() }
    }
    func update(_ content: AnyView, conversationID: UUID, streaming: Bool, hasMessages: Bool) {
        loadViewIfNeeded()
        if self.conversationID != conversationID {
            self.conversationID = conversationID; anchor = nil; disclosureAnchor = nil; scroll.contentInset.bottom = 0; lastOffset = 0; pendingJump = true; follow.followLatest()
        }
        self.streaming = streaming
        self.hasMessages = hasMessages
        host.rootView = content
        host.view.invalidateIntrinsicContentSize()
        scroll.setNeedsLayout()
    }
    func attach(_ viewport: ChatViewport) { self.viewport = viewport; viewport.controller = self }
    func detach() {
        displayLink?.invalidate(); displayLink = nil; frameDriver = nil; scroll.didLayout = nil; scroll.delegate = nil; dismissKeyboard = nil
        if viewport?.controller === self { viewport?.controller = nil }
    }
    func jumpToLatest() {
        loadViewIfNeeded()
        disclosureAnchor = nil; follow.followLatest(); pendingJump = true
        scroll.contentInset.bottom = 0
        // Stop an existing deceleration and perform the jump now, even when no
        // new token or size change would otherwise schedule a layout callback.
        scroll.setContentOffset(scroll.contentOffset, animated: false)
        host.view.layoutIfNeeded(); scroll.layoutIfNeeded()
        reconciling = true
        scroll.setContentOffset(CGPoint(x: 0, y: hasMessages ? maximumOffset : 0), animated: false)
        pendingJump = false; reconciling = false
        rememberPosition(); publishPosition()
        if streaming { startFollowingFrames() }
    }
    func pinDisclosure(_ id: UUID) {
        guard let marker = scroll.markers[id]?.value else { return }
        disclosureAnchor = (id, marker.convert(.zero, to: scroll).y - scroll.contentOffset.y)
        follow.beginReading(); displayLink?.isPaused = true; pendingJump = false; rememberPosition()
    }
    @objc private func readerPanned(_ gesture: UIPanGestureRecognizer) {
        if composerFocused && gesture.state == .changed && gesture.translation(in: scroll).y > 12 { dismissKeyboard?() }
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    private var naturalMaximumOffset: CGFloat { max(0, scroll.contentSize.height - scroll.bounds.height) }
    private var maximumOffset: CGFloat { max(0, scroll.contentSize.height + scroll.contentInset.bottom - scroll.bounds.height) }
    private var nearBottom: Bool { maximumOffset - scroll.contentOffset.y < 80 }

    private func reconcileLayout() {
        guard !reconciling, scroll.bounds.width > 0, scroll.bounds.height > 0 else { return }
        reconciling = true
        defer { reconciling = false }
        let viewportChanged = lastViewportSize != scroll.bounds.size
        let changed = lastContentSize != scroll.contentSize || viewportChanged
        if !scroll.isDragging && !scroll.isDecelerating && (changed || pendingJump) {
            let target: CGFloat
            // Empty chats show onboarding from its beginning, including at large text sizes.
            if pendingJump { target = hasMessages ? maximumOffset : 0 }
            else if let pinned = disclosureAnchor, let marker = scroll.markers[pinned.id]?.value {
                target = marker.convert(.zero, to: scroll).y - pinned.offset
                // A collapsed section can shorten the content below this offset.
                // Keep temporary space below it instead of clamping the reader
                // upward. Explicit latest-following or scrolling back releases it.
                scroll.contentInset.bottom = max(0, target - naturalMaximumOffset)
            }
            else if streaming && follow.isFollowing && !viewportChanged {
                startFollowingFrames()
                lastContentSize = scroll.contentSize; lastViewportSize = scroll.bounds.size
                publishPosition()
                return
            }
            else if follow.isFollowing { target = hasMessages ? maximumOffset : 0 }
            else if streaming && !viewportChanged { target = lastOffset }
            else if let anchor, let marker = scroll.markers[anchor.id]?.value {
                target = marker.convert(.zero, to: scroll).y - anchor.offset
            } else { target = lastOffset }
            scroll.setContentOffset(CGPoint(x: 0, y: min(max(0, target), maximumOffset)), animated: false)
            pendingJump = false
        }
        lastContentSize = scroll.contentSize; lastViewportSize = scroll.bounds.size
        // Token-driven remeasurement is not a new reading position. In particular,
        // do not sample a transient hosting/text-layout position back into the anchor.
        if !streaming || follow.isFollowing || scroll.isDragging || scroll.isDecelerating { rememberPosition() }
        publishPosition()
    }
    private func startFollowingFrames() {
        if displayLink == nil {
            let driver = ChatFrameDriver(); driver.owner = self; frameDriver = driver
            let link = CADisplayLink(target: driver, selector: #selector(ChatFrameDriver.tick(_:)))
            link.add(to: .main, forMode: .common); displayLink = link
        }
        lastFrameTime = 0; displayLink?.isPaused = false
    }
    fileprivate func advanceFollowingFrame(_ link: CADisplayLink) {
        guard streaming, follow.isFollowing, !scroll.isDragging, !scroll.isDecelerating else { link.isPaused = true; return }
        let elapsed = lastFrameTime == 0 ? link.duration : link.timestamp - lastFrameTime
        lastFrameTime = link.timestamp
        let current = scroll.contentOffset.y
        let next = CGFloat(ConversationFollow.advance(current: Double(current), bottom: Double(maximumOffset), elapsed: elapsed, scale: Double(scroll.window?.screen.scale ?? 3)))
        if abs(next - current) < 0.01 { link.isPaused = true; return }
        reconciling = true
        scroll.setContentOffset(CGPoint(x: 0, y: next), animated: false)
        rememberPosition()
        reconciling = false
        publishPosition()
    }
    private func rememberPosition() {
        lastOffset = scroll.contentOffset.y
        let tops = scroll.markers.compactMap { id, weakMarker -> (UUID, CGFloat)? in
            guard let marker = weakMarker.value, marker.window != nil else { return nil }
            return (id, marker.convert(.zero, to: scroll).y)
        }.sorted { $0.1 < $1.1 }
        // A zero-size background defaults to the response's center, which moves as it
        // grows. Explicit top markers stay fixed even when reading inside a long reply.
        let visible = tops.last { $0.1 <= scroll.contentOffset.y + 1 }
            ?? tops.first { $0.1 < scroll.contentOffset.y + scroll.bounds.height }
        if let visible { anchor = (visible.0, visible.1 - scroll.contentOffset.y) }
        scroll.markers = scroll.markers.filter { $0.value.value != nil }
    }
    private func publishPosition() {
        #if DEBUG
        let screenY = anchor.flatMap { scroll.markers[$0.id]?.value }.map { $0.convert(.zero, to: scroll.window).y } ?? 0
        scroll.accessibilityValue = "\(follow.isFollowing ? "following" : "reading")|\(Int(scroll.contentOffset.y.rounded()))|\(Int(maximumOffset.rounded()))|\(scroll.isDragging || scroll.isDecelerating ? "moving" : "idle")|\(Int(screenY.rounded()))"
        #endif
        let value = follow.isFollowing || nearBottom
        DispatchQueue.main.async { [weak self] in
            guard let self, self.viewport?.controller === self else { return }
            self.viewport?.updateNearBottom(value)
        }
    }
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        disclosureAnchor = nil
        reachedBottomDuringGesture = false
        follow.beginReading(); displayLink?.isPaused = true; pendingJump = false; rememberPosition()
        // The composer belongs to the enclosing SwiftUI root, outside this scroll view.
        // Native interactive dismissal alone does not resign that external first responder.
        if composerFocused && scrollView.panGestureRecognizer.velocity(in: scrollView).y > 0 { dismissKeyboard?() }
    }
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !reconciling else { return }
        if scrollView.isDragging || scrollView.isDecelerating {
            if disclosureAnchor == nil && scroll.contentInset.bottom > 0 && scroll.contentOffset.y <= naturalMaximumOffset {
                scroll.contentInset.bottom = 0
            }
            if maximumOffset - scroll.contentOffset.y <= 6 { reachedBottomDuringGesture = true }
            else if scrollView.isDragging && scrollView.panGestureRecognizer.velocity(in: scrollView).y > 0 { reachedBottomDuringGesture = false }
            rememberPosition()
        }
        publishPosition()
    }
    private func readerSettled() {
        if reachedBottomDuringGesture { follow.followLatest() }
        else { follow.userReached(distanceFromBottom: Double(maximumOffset - scroll.contentOffset.y)) }
        if follow.isFollowing { scroll.contentInset.bottom = 0 }
        rememberPosition(); publishPosition()
        if streaming && follow.isFollowing { startFollowingFrames() }
    }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) { if !decelerate { readerSettled() } }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { readerSettled() }
    func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool { follow.beginReading(); displayLink?.isPaused = true; return true }
}

@MainActor
private final class ChatFrameDriver: NSObject {
    weak var owner: ChatScrollController?
    @objc func tick(_ link: CADisplayLink) { owner?.advanceFollowingFrame(link) }
}

@MainActor
final class AnchoredChatScroll: UIScrollView {
    var didLayout: (() -> Void)?
    var markers: [UUID: WeakChatMarker] = [:]
    override func layoutSubviews() { super.layoutSubviews(); didLayout?() }
}
@MainActor
final class WeakChatMarker {
    weak var value: ChatMarkerView?
    init(_ value: ChatMarkerView) { self.value = value }
}
struct ChatScrollAnchor: UIViewRepresentable {
    let id: UUID
    func makeUIView(context: Context) -> ChatMarkerView { ChatMarkerView(id: id) }
    func updateUIView(_ view: ChatMarkerView, context: Context) { view.id = id; view.register() }
}
@MainActor
final class ChatMarkerView: UIView {
    var id: UUID
    init(id: UUID) { self.id = id; super.init(frame: .zero); isUserInteractionEnabled = false; isAccessibilityElement = false }
    required init?(coder: NSCoder) { fatalError("Use init(id:)") }
    override func didMoveToWindow() { super.didMoveToWindow(); register() }
    override func layoutSubviews() { super.layoutSubviews(); register() }
    func register() {
        var ancestor = superview
        while let current = ancestor {
            if let scroll = current as? AnchoredChatScroll {
                if scroll.markers[id]?.value !== self { scroll.markers[id] = WeakChatMarker(self); scroll.setNeedsLayout() }
                return
            }
            ancestor = current.superview
        }
    }
}
