import Foundation
import Combine

final class AppState: ObservableObject {
    @Published var seratoConnected = false
    @Published var dragMode = false
    @Published var bannerObstructed = false
    @Published var bannerManuallyHidden = false
}