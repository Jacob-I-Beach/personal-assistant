import Foundation
import SwiftUI

enum ChatDestination: Hashable, Identifiable {
    case artifact(UUID), file(UUID)
    var id: String {
        switch self { case .artifact(let id): "artifact-" + id.uuidString; case .file(let id): "file-" + id.uuidString }
    }
}
@MainActor
final class ChatNavigation: ObservableObject {
    @Published var destination: ChatDestination?
}
