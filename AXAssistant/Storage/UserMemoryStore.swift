import Foundation
import Observation

/// Durable facts the user has told the assistant, injected into every system prompt.
///
/// This is what makes the assistant feel like it knows you: "remind me to call mom" only
/// works twice if something remembered who mom is. Conversation history dies with the
/// thread; this doesn't.
///
/// Deliberately small. We measured the prompt at ~1,670 tokens and ~1.1 s of prefill per
/// generation, so memory is a budget, not a scratchpad: 20 facts of 120 characters is
/// about 300 tokens, and past that the cost lands on every request the user ever makes.
/// When it's full the oldest fact goes, because a memory that silently stops recording is
/// worse than one that visibly forgets.
@Observable @MainActor
final class UserMemoryStore {
    static let shared = UserMemoryStore()

    static let maxFacts = 20
    static let maxFactLength = 120

    private(set) var facts: [String] = []
    private static let key = "userMemoryFacts"

    private init() {
        facts = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
    }

    /// Returns false when the fact was a duplicate — the model re-stating something it
    /// already knows shouldn't consume budget.
    @discardableResult
    func remember(_ fact: String) -> Bool {
        let trimmed = String(fact.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxFactLength))
        guard !trimmed.isEmpty else { return false }
        guard !facts.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            return false
        }
        facts.append(trimmed)
        if facts.count > Self.maxFacts { facts.removeFirst(facts.count - Self.maxFacts) }
        save()
        return true
    }

    func forget(_ fact: String) {
        facts.removeAll { $0 == fact }
        save()
    }

    func forgetAll() {
        facts = []
        save()
    }

    private func save() {
        UserDefaults.standard.set(facts, forKey: Self.key)
    }
}
