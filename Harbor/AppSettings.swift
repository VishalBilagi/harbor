import Foundation

enum AppSettings {
    static let refreshIntervalKey = "harbor.refreshIntervalSeconds"
    static let defaultRefreshIntervalSeconds = 5.0
    static let minRefreshIntervalSeconds = 1.0
    static let maxRefreshIntervalSeconds = 20.0

    static func currentRefreshIntervalSeconds(userDefaults: UserDefaults = .standard) -> Int {
        let storedValue: Double

        if let number = userDefaults.object(forKey: refreshIntervalKey) as? NSNumber {
            storedValue = number.doubleValue
        } else {
            storedValue = defaultRefreshIntervalSeconds
        }

        let clampedValue = max(minRefreshIntervalSeconds, min(maxRefreshIntervalSeconds, storedValue))
        return Int(clampedValue.rounded())
    }
}
