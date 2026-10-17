import Foundation
import Combine

@MainActor
public protocol AppContainerProtocol {
    var localizationManager: LocalizationManager { get }
}

@MainActor
public final class AppContainer: ObservableObject, AppContainerProtocol {
    public static let shared = AppContainer()

    public let localizationManager: LocalizationManager

    public init(localizationManager: LocalizationManager = .shared) {
        self.localizationManager = localizationManager
    }
}
