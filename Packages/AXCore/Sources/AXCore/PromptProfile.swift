import Foundation

/// Per-model system-prompt tuning.
///
/// Models in the catalog span 0.6B to 8B across four vendors, and they fail differently:
/// the small ones drop the `<tool_call>` wrapper unless shown a worked example (measured:
/// that one addition moved Qwen3 1.7B from 0/9 to 9/9), while the larger ones handle
/// nuance but will happily over-fire a shortcut they were merely told about. One prompt
/// for all of them means every model gets the union of everyone else's guardrails.
///
/// Each field below is either **measured** on the eval suite or marked as a hypothesis
/// for the suite to settle — the point of running per-model evals is that these stop
/// being guesses.
public struct PromptProfile: Sendable, Equatable {
    /// Human name for reports, so a score is attributable to a prompt variant.
    public var name: String
    /// Show the worked `<tool_call>` example. MEASURED: required by every model ≤4B.
    public var includeWorkedExample: Bool
    /// Explain `repeat_steps`/`wait` so repetitive requests collapse into one call
    /// instead of a chain the model has to count through.
    public var includeWorkflowGuidance: Bool
    /// Spell the workflow syntax out with a filled-in example. HYPOTHESIS: small models
    /// need the literal string; larger ones infer it from the tool description.
    public var includeWorkflowExample: Bool
    /// Extra rules appended verbatim, for family-specific failure modes.
    public var extraRules: [String]
    /// Chain budget this model can actually sustain, if it differs from the user's
    /// setting. HYPOTHESIS: small models lose the thread past ~4 hand-backs.
    public var suggestedMaxToolIterations: Int?

    public init(
        name: String,
        includeWorkedExample: Bool = true,
        includeWorkflowGuidance: Bool = true,
        includeWorkflowExample: Bool = true,
        extraRules: [String] = [],
        suggestedMaxToolIterations: Int? = nil
    ) {
        self.name = name
        self.includeWorkedExample = includeWorkedExample
        self.includeWorkflowGuidance = includeWorkflowGuidance
        self.includeWorkflowExample = includeWorkflowExample
        self.extraRules = extraRules
        self.suggestedMaxToolIterations = suggestedMaxToolIterations
    }

    /// The conservative default: everything on. What every model got before profiles.
    public static let standard = PromptProfile(name: "standard")

    /// ≤2B. Terse and maximally explicit. The old "do exactly one thing" wording made
    /// Qwen 1.7B stop after the first leg of a compound request, so compound calls are
    /// allowed in one reply and the continuation fallback remains explicit.
    public static let small = PromptProfile(
        name: "small",
        extraRules: [
            "After every tool result, reread the original request and call the next unfinished action. Never repeat an action whose tool result says it succeeded.",
            "After repeat_steps succeeds, its inner actions are finished. Never call those inner tools again; continue only the action after the repeated sequence.",
            "Never explain what you are about to do — just emit the call.",
        ],
        suggestedMaxToolIterations: 4
    )

    /// 3B–8B Qwen-family: the strongest tool callers measured (9/9). They can be trusted
    /// with longer chains and don't need the workflow syntax spelled out.
    public static let capable = PromptProfile(
        name: "capable",
        includeWorkflowExample: false,
        suggestedMaxToolIterations: 8
    )

    /// Llama/Gemma/SmolLM: trained on other tool conventions, so tag discipline is the
    /// failure mode rather than tool choice. HYPOTHESIS — unmeasured on our suite.
    public static let otherVendor = PromptProfile(
        name: "other-vendor",
        extraRules: [
            """
            Use the <tool_call> XML tags exactly as shown. Do not use code fences, do not \
            write "function call:", and do not wrap the JSON in any other markup.
            """,
        ],
        suggestedMaxToolIterations: 5
    )

    /// Picks a profile from a Hugging Face repo id. Matching is on the id because that's
    /// the only thing the runtime reliably knows about a model.
    public static func forModel(_ modelID: String) -> PromptProfile {
        let id = modelID.lowercased()
        let isSmall = ["0.6b", "1.2b", "1.5b", "1.7b", "2b-", "-2b", "2b_"].contains { id.contains($0) }
        let isQwen = id.contains("qwen")

        if isSmall { return .small }
        if isQwen { return .capable }
        if ["llama", "gemma", "smollm", "lfm"].contains(where: { id.contains($0) }) {
            return .otherVendor
        }
        return .standard
    }
}
