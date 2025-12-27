import Foundation

extension NSNumber {
    var isBool: Bool {
        let boolID = CFBooleanGetTypeID()
        return CFGetTypeID(self) == boolID
    }
}
