import Foundation

class JSONPersistenceService {
    private let fileURL: URL
    private let userDefaults: UserDefaults
    private let fileManager: FileManager
    private let legacySavedKey = "SavedJSONs"

    init(
        fileURL: URL = JSONPersistenceService.defaultFileURL(),
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.userDefaults = userDefaults
        self.fileManager = fileManager
    }

    func save(_ parsedJSONs: [ParsedJSON]) {
        guard let encoded = try? JSONEncoder().encode(parsedJSONs) else { return }

        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoded.write(to: fileURL, options: .atomic)
        } catch {
            userDefaults.set(encoded, forKey: legacySavedKey)
        }
    }

    func load() -> [ParsedJSON] {
        if let fileData = try? Data(contentsOf: fileURL),
           let decodedJSONs = try? JSONDecoder().decode([ParsedJSON].self, from: fileData) {
            return decodedJSONs
        }

        guard let legacyData = userDefaults.data(forKey: legacySavedKey),
              let legacyJSONs = try? JSONDecoder().decode([ParsedJSON].self, from: legacyData) else {
            return []
        }

        save(legacyJSONs)
        return legacyJSONs
    }

    private static func defaultFileURL() -> URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return (applicationSupport ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("JSON Assistant", isDirectory: true)
            .appendingPathComponent("SavedJSONs.json")
    }
}
