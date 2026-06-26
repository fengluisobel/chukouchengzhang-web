import Foundation
import Combine

@MainActor
final class RemoteAppSettings: ObservableObject {
    private enum Keys {
        static let useRemoteAPI = "ckcz.useRemoteAPI"
        static let baseURLString = "ckcz.baseURLString"
        static let lastPresetID = "ckcz.lastPresetID"
    }

    @Published var useRemoteAPI: Bool {
        didSet { UserDefaults.standard.set(useRemoteAPI, forKey: Keys.useRemoteAPI) }
    }

    @Published var baseURLString: String {
        didSet { UserDefaults.standard.set(baseURLString, forKey: Keys.baseURLString) }
    }

    @Published var lastPresetID: String? {
        didSet { UserDefaults.standard.set(lastPresetID, forKey: Keys.lastPresetID) }
    }

    init() {
        self.useRemoteAPI = UserDefaults.standard.object(forKey: Keys.useRemoteAPI) as? Bool ?? AppConfig.defaultUseRemoteAPI
        self.baseURLString = UserDefaults.standard.string(forKey: Keys.baseURLString) ?? AppConfig.defaultBaseURLString
        self.lastPresetID = UserDefaults.standard.string(forKey: Keys.lastPresetID)
    }

    var trimmedBaseURLString: String {
        baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var baseURL: URL? {
        URL(string: trimmedBaseURLString)
    }

    func applyDefaults() {
        useRemoteAPI = AppConfig.defaultUseRemoteAPI
        baseURLString = AppConfig.defaultBaseURLString
        lastPresetID = AppConfig.defaultUseRemoteAPI ? "simulator-localhost" : "mock"
    }

    func applyPreset(_ preset: RemoteEndpointPreset) {
        useRemoteAPI = preset.enablesRemote
        if let urlString = preset.urlString {
            baseURLString = urlString
        }
        lastPresetID = preset.id
    }
}
