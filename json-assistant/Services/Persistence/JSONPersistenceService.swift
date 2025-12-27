import Foundation

class JSONPersistenceService {
    private let userDefaults = UserDefaults.standard
    private let savedKey = "SavedJSONs"

    func save(_ parsedJSONs: [ParsedJSON]) {
        if let encoded = try? JSONEncoder().encode(parsedJSONs) {
            userDefaults.set(encoded, forKey: savedKey)
        }
    }

    func load() -> [ParsedJSON] {
        if let savedJSONs = userDefaults.data(forKey: savedKey) {
            if let decodedJSONs = try? JSONDecoder().decode([ParsedJSON].self, from: savedJSONs) {
                return decodedJSONs
            }
        }
        return []
    }
}
