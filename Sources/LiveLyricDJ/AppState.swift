import Foundation
import Combine

final class AppState: ObservableObject {
    @Published var seratoConnected = false
    @Published var dragMode = false
}