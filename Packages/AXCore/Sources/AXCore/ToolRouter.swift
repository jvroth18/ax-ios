import Foundation

/// Chooses which tool schemas to put in the system prompt for a given request.
///
/// Measured motivation: the full 14-tool prompt is ~1,670 tokens and costs ~1.1 s of
/// prefill per generation on the Mac harness (~2 s at phone speeds), paid again on every
/// iteration of a chain. Most of those schemas are irrelevant to any one request.
///
/// The danger is obvious and worth stating plainly: a router that omits the right tool
/// makes the assistant unable to do something it can do, and it fails *silently* — the
/// model simply answers in prose. Three deliberate choices keep that from happening
/// quietly:
///
/// 1. **Selection is additive, never subtractive by guess.** A tool is kept when the
///    request looks like it, not dropped when it doesn't.
/// 2. **Weak evidence means keep everything.** If nothing scores above the floor, the
///    request is one the router doesn't understand, and the full catalog is returned.
/// 3. **It is off by default** and reported in the eval artifact, so the score with
///    routing on is comparable against the score with it off before anyone trusts it.
public enum ToolRouter {

    /// Tools always kept regardless of score. `repeat_steps` and `wait` are here because
    /// they compose with every other tool: a request that needs them rarely names them.
    public static let alwaysInclude: Set<String> = ["repeat_steps", "wait"]

    /// Words too common to carry signal. Kept small on purpose — an aggressive stop list
    /// is another way to lose the one word that mattered.
    private static let noise: Set<String> = [
        "the", "a", "an", "and", "or", "to", "for", "of", "my", "me", "i", "please",
        "can", "you", "it", "that", "this", "is", "are", "do", "with", "on", "off", "at",
    ]

    /// Returns the schemas to include, and whether the catalog was narrowed at all.
    ///
    /// - Parameters:
    ///   - limit: how many scored tools to keep before the always-include set is added.
    ///   - floor: minimum score to count as evidence. Below it, everything is returned.
    ///     Defaults to 2 — the value only a *name* match can reach — so narrowing
    ///     requires the request to have named a tool rather than merely sharing a common
    ///     word with some description. A unit test found the alternative: "what do you
    ///     think about all this?" scored a stray description word and cut the catalog to
    ///     four tools, which is the silent-capability-loss failure this router exists to
    ///     avoid.
    public static func select(
        from tools: [ToolSpec],
        for request: String,
        limit: Int = 6,
        floor: Int = 2
    ) -> (tools: [ToolSpec], narrowed: Bool) {
        guard tools.count > limit else { return (tools, false) }
        let words = tokenize(request)
        guard !words.isEmpty else { return (tools, false) }

        let scored = tools.map {
            (spec: $0, score: score(spec: $0, against: words),
             strong: strongScore(spec: $0, against: words))
        }
        // Only identifiers may *trigger* narrowing. Prose can rank, never decide: a test
        // caught `create_reminder` scoring two points on "what … about" purely because its
        // parameter description reads "What to remind the user about".
        let evidence = scored.filter { $0.strong >= floor }
        // Nothing matched: this is a request the router doesn't understand, which is
        // exactly when guessing is most expensive. Send everything.
        guard !evidence.isEmpty else { return (tools, false) }

        let ranked = evidence.sorted { $0.score > $1.score }.prefix(limit).map(\.spec.name)
        let keep = Set(ranked).union(alwaysInclude)
        let selected = tools.filter { keep.contains($0.name) }
        return (selected, selected.count < tools.count)
    }

    /// Evidence from *identifiers only*: the tool's name (double weight), its parameter
    /// keys, and its enum values. These are things a request can only match by being about
    /// the tool, unlike description prose which is ordinary English.
    static func strongScore(spec: ToolSpec, against words: Set<String>) -> Int {
        let nameWords = tokenize(spec.name.replacingOccurrences(of: "_", with: " "))
        var identifiers: Set<String> = []
        for (key, schema) in spec.parameters.properties ?? [:] {
            identifiers.formUnion(tokenize(key.replacingOccurrences(of: "_", with: " ")))
            for value in schema.enumValues ?? [] { identifiers.formUnion(tokenize(value)) }
        }
        return words.intersection(nameWords).count * 2 + words.intersection(identifiers).count
    }

    /// Strong evidence plus description prose. Used for ranking among tools that already
    /// cleared the narrowing gate.
    static func score(spec: ToolSpec, against words: Set<String>) -> Int {
        var descriptive = tokenize(spec.description)
        for schema in (spec.parameters.properties ?? [:]).values {
            descriptive.formUnion(tokenize(schema.description ?? ""))
        }
        return strongScore(spec: spec, against: words) + words.intersection(descriptive).count
    }

    static func tokenize(_ text: String) -> Set<String> {
        let parts = text.lowercased().split { !$0.isLetter && !$0.isNumber }
        return Set(parts.map(String.init).filter { $0.count > 2 && !noise.contains($0) })
    }
}
