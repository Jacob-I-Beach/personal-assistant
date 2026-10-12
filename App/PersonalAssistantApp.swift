import SwiftUI
import AppIntents

@main
struct PersonalAssistantApp: App {
    @UIApplicationDelegateAdaptor(RemotePushRegistration.self) private var pushRegistration
    @StateObject private var model: AppModel
    init() {
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        AppDependencyManager.shared.add(dependency: model)
        AssistantShortcuts.updateAppShortcutParameters()
    }
    var body: some Scene {
        WindowGroup { RootView().environmentObject(model) }
    }
}
