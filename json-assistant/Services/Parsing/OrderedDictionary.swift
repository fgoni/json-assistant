import Foundation

class OrderedDictionary {
    private var keys: [String] = []
    private var dict: [String: Any] = [:]

    subscript(key: String) -> Any? {
        get { return dict[key] }
        set {
            if newValue == nil {
                dict.removeValue(forKey: key)
                keys.removeAll { $0 == key }
            } else {
                if dict[key] == nil {
                    keys.append(key)
                }
                dict[key] = newValue
            }
        }
    }

    var orderedPairs: [(String, Any)] {
        return keys.map { ($0, dict[$0]!) }
    }
}
