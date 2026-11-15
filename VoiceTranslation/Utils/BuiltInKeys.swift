import Foundation

/// Public builds never contain service credentials. Each user supplies their own key.
/// Kept as an empty compatibility shim for the settings interface.
enum BuiltInKeys {
    static let openAIKey = ""
    static let customAPIKey = ""
    static let hasOpenAIKey = false
    static let hasCustomAPIKey = false
}
