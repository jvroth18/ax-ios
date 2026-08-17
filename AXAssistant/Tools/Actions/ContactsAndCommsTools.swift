import Foundation
import Contacts
import UIKit
import AXCore

struct ContactsTool: AXTool {
    let spec = ToolSpec(
        name: "find_contact",
        description: "Look up a contact's phone number by name.",
        parameters: JSONSchema(
            type: .object,
            properties: ["name": JSONSchema(type: .string)],
            required: ["name"]
        ),
        risk: .safe
    )

    func run(_ call: ToolCall) async throws -> ToolResult {
        guard let name = call.string("name") else { throw AXToolError.missingArgument("name") }
        let store = CNContactStore()
        try await store.requestAccess(for: .contacts)
        let contacts = try store.unifiedContacts(
            matching: CNContact.predicateForContacts(matchingName: name),
            keysToFetch: [
                CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey,
            ] as [CNKeyDescriptor]
        )
        guard let contact = contacts.first else { return .failure("No contact named \(name).") }
        let numbers = contact.phoneNumbers.map { entry in
            "\(entry.label.map(CNLabeledValue<NSString>.localizedString(forLabel:)) ?? "phone"): \(entry.value.stringValue)"
        }
        let fullName = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
        return .ok("\(fullName) — \(numbers.joined(separator: ", "))")
    }
}

struct CallTool: AXTool {
    let spec = ToolSpec(
        name: "call_number",
        description: "Start a phone call to a number (get the number with find_contact first).",
        parameters: JSONSchema(
            type: .object,
            properties: ["number": JSONSchema(type: .string, description: "Digits, may include +")],
            required: ["number"]
        ),
        risk: .confirm
    )

    func run(_ call: ToolCall) async throws -> ToolResult {
        guard let raw = call.string("number") else { throw AXToolError.missingArgument("number") }
        let digits = raw.filter { $0.isNumber || $0 == "+" }
        guard let url = URL(string: "tel:\(digits)") else {
            throw AXToolError.badArgument("number", "not a dialable number")
        }
        guard await MainActor.run(body: { UIApplication.shared.canOpenURL(url) }) else {
            throw AXToolError.notAvailable("This device cannot place calls.")
        }
        await MainActor.run { UIApplication.shared.open(url) }
        return .ok("Calling \(digits). iOS shows its own call confirmation.")
    }
}

struct MessageTool: AXTool {
    let spec = ToolSpec(
        name: "compose_message",
        description: """
        Open Messages with a recipient and prefilled text. iOS never allows sending \
        silently — the user reviews and taps Send themselves.
        """,
        parameters: JSONSchema(
            type: .object,
            properties: [
                "number": JSONSchema(type: .string, description: "Recipient phone number"),
                "body": JSONSchema(type: .string, description: "Message text"),
            ],
            required: ["number", "body"]
        ),
        risk: .safe  // safe because iOS itself forces user review before send
    )

    func run(_ call: ToolCall) async throws -> ToolResult {
        guard let number = call.string("number") else { throw AXToolError.missingArgument("number") }
        guard let body = call.string("body") else { throw AXToolError.missingArgument("body") }
        var components = URLComponents(string: "sms:\(number.filter { $0.isNumber || $0 == "+" })")
        components?.queryItems = [URLQueryItem(name: "body", value: body)]
        guard let url = components?.url else { throw AXToolError.badArgument("number", "invalid") }
        await MainActor.run { UIApplication.shared.open(url) }
        return .ok("Opened Messages with the draft. The user must tap Send.")
    }
}
