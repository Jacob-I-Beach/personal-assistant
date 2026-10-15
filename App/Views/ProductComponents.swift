import AssistantCore
import SwiftUI

extension AppModel {
    var selectedAvailability: CapabilityAvailability {
        let title = modelTitle, route = modelLocation
        if settings.localOnly && ![.appleOnDevice, .localMLX].contains(settings.choice) { return .init(capability: title, route: route, state: .blocked, detail: "On-device-only mode is enabled. Choose an on-device model to reply.", recovery: .models) }
        switch settings.choice {
        case .appleOnDevice, .appleCloud:
            let value = settings.choice == .appleOnDevice ? appleDevice : appleCloud
            return .init(capability: title, route: route, state: value.isAvailable ? .ready : .unavailable, detail: value.isAvailable ? "Ready for a conversation" : value.detail, recovery: value.isAvailable ? nil : .models)
        case .localMLX:
            guard downloadedModelIDs.contains(settings.localRepository) else { return .init(capability: title, route: route, state: .needsSetup, detail: "Download or import this model before using it.", recovery: .models) }
            if !localContextBudget().fits { return .init(capability: title, route: route, state: .blocked, detail: "The selected context needs more memory headroom. Your model and context choice are kept.", recovery: .models) }
            return .init(capability: title, route: route, state: .ready, detail: "Downloaded on this iPhone. Memory is checked again when loading.")
        case .chatGPT:
            if isConnecting || modelCatalog.phase == .refreshing { return .init(capability: title, route: route, state: .checking, detail: "Checking the connected account and model catalog", recovery: .models) }
            if shouldOfferChatGPTSignIn { return .init(capability: title, route: route, state: .needsSetup, detail: "Connect ChatGPT or choose an on-device model.", recovery: .models) }
            if computerAccountNeedsAttention { return .init(capability: title, route: route, state: .unavailable, detail: computerAccountDetail, recovery: .connections) }
            guard modelCatalog.phase == .ready, !settings.chatGPTModel.isEmpty, chatGPTModels.contains(where: { $0.id == settings.chatGPTModel }) else { return .init(capability: title, route: route, state: .unavailable, detail: "The account is saved; current model availability could not be confirmed.", recovery: .models) }
            return .init(capability: title, route: route, state: .ready, detail: "Account connected · model catalog available", observedAt: modelCatalog.updatedAt)
        case .openAI, .compatibleServer:
            return .init(capability: title, route: route, state: settings.endpoint == nil ? .needsSetup : .checking, detail: "The configured service is checked when you send a request.", recovery: .settings)
        }
    }
}
enum AssistantStyle {
    static let page: CGFloat = 20
    static let gap: CGFloat = 12
    static let cardRadius: CGFloat = 18
    static let controlHeight: CGFloat = 44
    static let secondarySurface = Color(uiColor: .secondarySystemBackground)
    static let quietSurface = Color(uiColor: .tertiarySystemFill)
}
struct ReadinessRow: View {
    @EnvironmentObject private var model: AppModel
    var showsReady = false
    var body: some View {
        let value = model.selectedAvailability
        if showsReady || value.state != .ready {
            VStack(alignment: .leading, spacing: 8) {
                Label(value.capability, systemImage: value.state == .ready ? "checkmark.circle" : value.state == .checking ? "arrow.triangle.2.circlepath" : "info.circle").font(.subheadline.weight(.medium))
                Text(value.detail).font(.caption).foregroundStyle(.secondary)
                if let recovery = value.recovery, recovery != model.rootPresentation { Button(value.state == .needsSetup ? "Choose how to reply" : "Review connection or model") { model.present(recovery) }.frame(minHeight: AssistantStyle.controlHeight) }
            }.accessibilityElement(children: .contain)
        }
    }
}
struct TaskStatusStrip: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        if model.isRunning {
            HStack(alignment: .top, spacing: 10) {
                if model.nativeAction == nil { ProgressView().controlSize(.small) } else { Image(systemName: "hand.raised") }
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.nativeAction?.title ?? model.activity ?? "Working on your request").font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                    if let request = model.nativeAction { Button(request.kind == .question ? "Answer" : "Review") { model.present(.review(request.id)) }.frame(minHeight: AssistantStyle.controlHeight) }
                    else { Button("View task") { model.present(.task) }.font(.caption).frame(minHeight: AssistantStyle.controlHeight) }
                }
                Spacer(minLength: 0)
                if let owner = model.executionOwner { Button("Stop", role: .destructive) { model.stop(owner: owner) }.frame(minHeight: AssistantStyle.controlHeight) }
            }.padding(AssistantStyle.gap).background(AssistantStyle.secondarySurface, in: RoundedRectangle(cornerRadius: AssistantStyle.cardRadius))
                .accessibilityIdentifier("task-status-strip")
        }
    }
}
struct AttachmentPreparationView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        ForEach(model.attachmentPreparation.filter { $0.conversationID == model.conversation.id && $0.state != .ready }) { value in
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(value.source, systemImage: value.state == .preparing ? "doc.badge.clock" : "exclamationmark.circle").font(.caption.weight(.medium))
                    Text(value.detail.isEmpty ? "Preparing attachment" : value.detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if value.state != .preparing { Button("Dismiss") { model.attachmentPreparation.removeAll { $0.id == value.id } }.font(.caption).frame(minHeight: 44) }
            }
        }
        if !model.attachedCaptureIDs.isEmpty && model.settings.choice == .appleOnDevice {
            Text("This Apple model uses saved image observations and text; it cannot inspect the original pixels. The image stays attached.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct OutputRow: View {
    let value: OutputPresentation
    let symbol: String
    var body: some View {
        HStack(spacing: AssistantStyle.gap) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.secondary).frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(value.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
                Text((value.isInput ? "Imported original" : value.revision.map { "Revision \($0)" } ?? "Saved output") + " · " + ByteCountFormatter.string(fromByteCount: Int64(value.bytes), countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                Text(value.updatedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                if value.health { Label("Health-derived", systemImage: "heart").font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 8).frame(minHeight: AssistantStyle.controlHeight).accessibilityElement(children: .combine)
    }
}

struct LocalRecoveryRow: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        if let recovery = model.localRecovery, recovery.conversationID == nil || recovery.conversationID == model.conversation.id {
            VStack(alignment: .leading, spacing: 8) {
                Label(recovery.title, systemImage: "exclamationmark.circle").font(.subheadline.weight(.medium))
                Text(recovery.detail).font(.caption).foregroundStyle(.secondary)
                Text(recovery.retained).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(recovery.category == .connection ? "Review connection" : "Inspect Library") { model.present(recovery.category == .connection ? .connections : .library) }.frame(minHeight: 44)
                    Spacer(); Button("Dismiss") { model.localRecovery = nil }.frame(minHeight: 44)
                }
            }.padding(AssistantStyle.gap).background(AssistantStyle.secondarySurface, in: RoundedRectangle(cornerRadius: AssistantStyle.cardRadius)).accessibilityIdentifier("local-recovery")
        }
    }
}
