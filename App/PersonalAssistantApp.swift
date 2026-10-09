import SwiftUI
import AppIntents

@main
struct PersonalAssistantApp: App {
    @StateObject private var model: AppModel
    init() {
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        AppDependencyManager.shared.add(dependency: model)
    }
    var body: some Scene {
        WindowGroup { RootView().environmentObject(model) }
    }
}
