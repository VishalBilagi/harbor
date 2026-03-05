import Foundation

enum AppSettings {
    static let refreshIntervalKey = "harbor.refreshIntervalSeconds"
    static let defaultRefreshIntervalSeconds = 5.0
    static let minRefreshIntervalSeconds = 1.0
    static let maxRefreshIntervalSeconds = 20.0
}
