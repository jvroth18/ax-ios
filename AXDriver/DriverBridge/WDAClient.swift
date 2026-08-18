#if AX_DRIVER
import Foundation
import UIKit

/// Minimal HTTP client for a WebDriverAgent runner listening on this device
/// (see AXDriver/WDA-SETUP.md). WDA speaks the WebDriver protocol over localhost.
struct WDAClient {
    var baseURL = URL(string: "http://127.0.0.1:8100")!
    private var sessionID: String?

    struct Status: Decodable {
        struct Value: Decodable { let ready: Bool }
        let value: Value
    }

    func isRunning() async -> Bool {
        guard let status: Status = try? await get("/status") else { return false }
        return status.value.ready
    }

    mutating func createSession() async throws {
        struct Response: Decodable {
            let sessionId: String
        }
        let response: Response = try await post("/session", body: [
            "capabilities": ["alwaysMatch": [String: String]()],
        ])
        sessionID = response.sessionId
    }

    func screenshot() async throws -> UIImage {
        struct Response: Decodable { let value: String }
        let response: Response = try await get("/screenshot")
        guard let data = Data(base64Encoded: response.value), let image = UIImage(data: data) else {
            throw WDAError.badScreenshot
        }
        return image
    }

    func tap(x: Double, y: Double) async throws {
        try await postSession("/wda/tap", body: ["x": x, "y": y])
    }

    func typeText(_ text: String) async throws {
        try await postSession("/wda/keys", body: ["value": text.map(String.init)])
    }

    func launchApp(bundleID: String) async throws {
        try await postSession("/wda/apps/launch", body: ["bundleId": bundleID])
    }

    func pressHome() async throws {
        try await postSession("/wda/homescreen", body: [:] as [String: String])
    }

    /// One screenful upward scroll (drag from lower-middle to upper-middle).
    func scrollUp(screenWidth: Double, screenHeight: Double) async throws {
        try await postSession("/wda/dragfromtoforduration", body: [
            "fromX": screenWidth / 2, "fromY": screenHeight * 0.75,
            "toX": screenWidth / 2, "toY": screenHeight * 0.25,
            "duration": 0.3,
        ])
    }

    enum WDAError: Error {
        case noSession
        case badScreenshot
        case http(Int)
    }

    // MARK: - Plumbing

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let (data, response) = try await URLSession.shared.data(from: baseURL.appendingPathComponent(path))
        try check(response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func post<T: Decodable>(_ path: String, body: some Encodable) async throws -> T {
        let data = try await postRaw(path, body: body)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func postSession(_ path: String, body: some Encodable) async throws {
        guard let sessionID else { throw WDAError.noSession }
        _ = try await postRaw("/session/\(sessionID)\(path)", body: body)
    }

    private func postRaw(_ path: String, body: some Encodable) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response)
        return data
    }

    private func check(_ response: URLResponse) throws {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw WDAError.http(http.statusCode)
        }
    }
}
#endif
