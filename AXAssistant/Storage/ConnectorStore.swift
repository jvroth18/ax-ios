import Foundation

/// A user-registered HTTP endpoint the model may call via the http_request tool.
/// The allowlist IS the security model: the model can only name connectors, never URLs.
struct EndpointConnector: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String          // what the model calls it, e.g. "talky stats"
    var url: String           // https only, enforced at call time
    var method: String = "GET"
    var descriptionForModel: String = ""  // e.g. "returns today's demo bookings as JSON"
}

/// A user-registered "open this app and read the screen" task for the summarize_app tool
/// (AXDriver builds only — config is stored regardless so it survives build-flag changes).
struct AppSummaryConnector: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String          // e.g. "x notifications"
    var bundleID: String      // e.g. "com.atebits.Tweetie2"
    var scrolls: Int = 1      // extra screenfuls to capture after the first
    var prompt: String = "Summarize what is shown on this screen in 2-3 spoken sentences."
}
