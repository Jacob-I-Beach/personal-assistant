import SwiftUI
import UIKit

@MainActor
final class ChatViewport: ObservableObject {
    @Published private(set) var nearBottom = true
    weak var controller: ChatScrollController?
    func jumpToLatest() { controller?.jumpToLatest() }
    func updateNearBottom(_ value: Bool) { if nearBottom != value { nearBottom = value } }
}

/// Eager layout within the bounded message window avoids estimated lazy-row heights.
/// The reader's actual visible row and offset survive content and keyboard size changes.
struct StableChatScrollView<Content: View>: UIViewControllerRepresentable {
    let conversationID: UUID
    let isStreaming: Bool
    let viewport: ChatViewport
    @ViewBuilder var content: () -> Content

    func makeUIViewController(context: Context) -> ChatScrollController {
        let controller = ChatScrollController(viewport: viewport)
        controller.update(AnyView(content().environment(\.self, context.environment)), conversationID: conversationID, streaming: isStreaming)
        return controller
    }
    func updateUIViewController(_ controller: ChatScrollController, context: Context) {
        controller.update(AnyView(content().environment(\.self, context.environment)), conversationID: conversationID, streaming: isStreaming)
    }
    static func dismantleUIViewController(_ controller: ChatScrollController, coordinator: ()) { controller.detach() }
}

@MainActor
final class ChatScrollController: UIViewController, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    private let scroll = AnchoredChatScroll()
    private let host = UIHostingController(rootView: AnyView(EmptyView()))
    private weak var viewport: ChatViewport?
    private var conversationID: UUID?
    private var streaming = false
    private var following = true
    private var pendingJump = true
    private var reconciling = false
    private var lastContentSize = CGSize.zero
    private var lastViewportSize = CGSize.zero
    private var anchor: (id: UUID, offset: CGFloat)?
    private var lastOffset: CGFloat = 0

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
        let tap = UITapGestureRecognizer(target: self, action: #selector(readerTapped))
        tap.cancelsTouchesInView = false; tap.delegate = self; scroll.addGestureRecognizer(tap)
    }
    func update(_ content: AnyView, conversationID: UUID, streaming: Bool) {
        loadViewIfNeeded()
        if self.conversationID != conversationID {
            self.conversationID = conversationID; anchor = nil; lastOffset = 0; pendingJump = true; following = true
        }
        self.streaming = streaming
        host.rootView = content
        host.view.invalidateIntrinsicContentSize()
        scroll.setNeedsLayout()
    }
    func detach() { scroll.didLayout = nil; scroll.delegate = nil; viewport?.controller = nil }
    func jumpToLatest() { following = true; pendingJump = true; scroll.setNeedsLayout() }
    @objc private func readerTapped() { following = false }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    private var maximumOffset: CGFloat { max(0, scroll.contentSize.height - scroll.bounds.height) }
    private var nearBottom: Bool { maximumOffset - scroll.contentOffset.y < 80 }

    private func reconcileLayout() {
        guard !reconciling, scroll.bounds.width > 0, scroll.bounds.height > 0 else { return }
        reconciling = true
        defer { reconciling = false }
        let changed = lastContentSize != scroll.contentSize || lastViewportSize != scroll.bounds.size
        if !scroll.isDragging && !scroll.isDecelerating && (changed || pendingJump) {
            let target: CGFloat
            if pendingJump || (streaming && following) { target = maximumOffset }
            else if let anchor, let marker = scroll.markers[anchor.id]?.value {
                target = marker.convert(.zero, to: scroll).y - anchor.offset
            } else { target = lastOffset }
            scroll.setContentOffset(CGPoint(x: 0, y: min(max(0, target), maximumOffset)), animated: false)
            pendingJump = false
        }
        lastContentSize = scroll.contentSize; lastViewportSize = scroll.bounds.size
        rememberPosition()
        publishPosition()
    }
    private func rememberPosition() {
        lastOffset = scroll.contentOffset.y
        let visible = scroll.markers.compactMap { id, weakMarker -> (UUID, CGRect)? in
            guard let marker = weakMarker.value, marker.window != nil else { return nil }
            let rect = marker.convert(marker.bounds, to: scroll)
            guard rect.maxY > scroll.contentOffset.y + 1, rect.minY < scroll.contentOffset.y + scroll.bounds.height else { return nil }
            return (id, rect)
        }.sorted { $0.1.minY < $1.1.minY }
        if let first = visible.first { anchor = (first.0, first.1.minY - scroll.contentOffset.y) }
        scroll.markers = scroll.markers.filter { $0.value.value != nil }
    }
    private func publishPosition() {
        let value = nearBottom
        DispatchQueue.main.async { [weak self] in self?.viewport?.updateNearBottom(value) }
    }
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { following = false; pendingJump = false; rememberPosition() }
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !reconciling else { return }
        if scrollView.isDragging || scrollView.isDecelerating { rememberPosition() }
        publishPosition()
    }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) { if !decelerate { following = nearBottom; rememberPosition() } }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { following = nearBottom; rememberPosition() }
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
