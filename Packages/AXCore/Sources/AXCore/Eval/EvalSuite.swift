import Foundation

/// The golden suite: 43 cases across six classes, all written against `EvalClock.pinned`
/// (Wednesday 2026-08-19 14:30 America/New_York).
///
/// Day arithmetic from the reference, for reading the `dayOffset`s below:
///   0 Wed 8/19 · +1 Thu 8/20 · +2 Fri 8/21 · +3 Sat 8/22 · +4 Sun 8/23 · +5 Mon 8/24
///
/// Transcripts are written as speech, not as prompts — these are things said out loud to a
/// phone, contractions and all, because that is what `Transcriber` actually hands the model.
public enum EvalSuite {

    /// Bump when cases change semantics, so an old report is never silently compared to a
    /// new suite.
    public static let version = "2026.08.19-1"

    public static var all: [EvalCase] {
        singleTool + dateExtraction + negative + multiStep + ambiguity + spuriousExtra + workflow
    }

    public static func cases(in caseClass: EvalCaseClass) -> [EvalCase] {
        all.filter { $0.caseClass == caseClass }
    }

    // MARK: - Single tool (10)

    public static let singleTool: [EvalCase] = [
        EvalCase(
            id: "single-flashlight-on",
            transcript: "Turn on the flashlight",
            caseClass: .singleTool,
            expected: [ExpectedCall("toggle_flashlight", ["state": .caseInsensitive("on")])]
        ),
        EvalCase(
            id: "single-flashlight-indirect",
            transcript: "It's pitch black in here, can you give me some light",
            caseClass: .singleTool,
            expected: [ExpectedCall("toggle_flashlight", ["state": .caseInsensitive("on")])],
            note: "Intent stated as a complaint, not a command."
        ),
        EvalCase(
            id: "single-music-pause",
            transcript: "Pause the music",
            caseClass: .singleTool,
            expected: [ExpectedCall("play_music", ["action": .caseInsensitive("pause")])]
        ),
        EvalCase(
            id: "single-music-next",
            transcript: "Skip this song",
            caseClass: .singleTool,
            expected: [ExpectedCall("play_music", ["action": .caseInsensitive("next")])]
        ),
        EvalCase(
            id: "single-timer-10",
            transcript: "Set a timer for 10 minutes",
            caseClass: .singleTool,
            expected: [ExpectedCall("set_timer", ["minutes": .number(10)])]
        ),
        EvalCase(
            id: "single-timer-90-seconds",
            transcript: "Set a timer for a minute and a half",
            caseClass: .singleTool,
            expected: [ExpectedCall("set_timer", ["minutes": .number(1.5, tolerance: 0.01)])],
            note: "Sub-minute duration expressed in words; minutes is a number, not an integer."
        ),
        EvalCase(
            id: "single-calendar-read",
            transcript: "What's on my calendar today?",
            caseClass: .singleTool,
            expected: [ExpectedCall("read_next_events")]
        ),
        EvalCase(
            id: "single-open-maps",
            transcript: "Open Maps",
            caseClass: .singleTool,
            expected: [ExpectedCall("open_app", ["app": .caseInsensitive("maps")])]
        ),
        EvalCase(
            id: "single-find-contact",
            transcript: "What's Dave's phone number?",
            caseClass: .singleTool,
            expected: [ExpectedCall("find_contact", ["name": .contains("dave")])]
        ),
        EvalCase(
            id: "single-run-shortcut",
            transcript: "Run my Goodnight shortcut",
            caseClass: .singleTool,
            expected: [ExpectedCall("run_shortcut", ["name": .exact("Goodnight")])],
            note: "Exact match: the tool refuses names that aren't registered verbatim."
        ),
    ]

    // MARK: - Date extraction (12)

    /// The class the old harness could not score at all. Every `due`/`start` here is
    /// compared as an instant, so a model that emits a syntactically valid but semantically
    /// wrong date fails instead of passing on key existence.
    public static let dateExtraction: [EvalCase] = [
        EvalCase(
            id: "date-reminder-5pm-today",
            transcript: "Remind me to call mom at 5pm today",
            caseClass: .dateExtraction,
            expected: [ExpectedCall("create_reminder", [
                "title": .contains("mom"),
                "due": .resolvedDate(.wallClock(dayOffset: 0, hour: 17, minute: 0)),
            ])],
            note: """
            The case that would have caught the create_reminder bug: the prompt teaches a \
            zone-less ISO string, which the tool's own parser used to reject. Argument \
            scoring alone passes it; only execution validation catches it.
            """
        ),
        EvalCase(
            id: "date-calendar-lunch-tomorrow-noon",
            transcript: "Put lunch with Sarah on my calendar tomorrow at noon",
            caseClass: .dateExtraction,
            expected: [ExpectedCall("create_calendar_event", [
                "title": .contains("sarah"),
                "start": .resolvedDate(.wallClock(dayOffset: 1, hour: 12, minute: 0)),
            ])]
        ),
        EvalCase(
            id: "date-reminder-tomorrow-8am",
            transcript: "Remind me to take the trash out tomorrow morning at eight",
            caseClass: .dateExtraction,
            expected: [ExpectedCall("create_reminder", [
                "title": .contains("trash"),
                "due": .resolvedDate(.wallClock(dayOffset: 1, hour: 8, minute: 0)),
            ])],
            note: "Spelled-out hour plus an AM/PM cue carried only by the word \"morning\"."
        ),
        EvalCase(
            id: "date-reminder-tonight-9",
            transcript: "Remind me to take my medicine tonight at nine",
            caseClass: .dateExtraction,
            expected: [ExpectedCall("create_reminder", [
                "title": .contains("medicine"),
                "due": .resolvedDate(.wallClock(dayOffset: 0, hour: 21, minute: 0)),
            ])],
            note: "\"Tonight\" is still today at 14:30 — a model that adds a day is wrong."
        ),
        EvalCase(
            id: "date-calendar-friday-9am",
            transcript: "Schedule a dentist appointment for Friday at 9am",
            caseClass: .dateExtraction,
            expected: [ExpectedCall("create_calendar_event", [
                "title": .contains("dentist"),
                "start": .resolvedDate(.wallClock(dayOffset: 2, hour: 9, minute: 0)),
            ])],
            note: "Named weekday: Friday is 2026-08-21, two days after the reference."
        ),
        EvalCase(
            id: "date-reminder-saturday-noon",
            transcript: "Remind me to call the vet on Saturday at noon",
            caseClass: .dateExtraction,
            expected: [ExpectedCall("create_reminder", [
                "title": .contains("vet"),
                "due": .resolvedDate(.wallClock(dayOffset: 3, hour: 12, minute: 0)),
            ])]
        ),
        EvalCase(
            id: "date-reminder-in-20-minutes",
            transcript: "Remind me in twenty minutes to check the oven",
            caseClass: .dateExtraction,
            expected: [ExpectedCall("create_reminder", [
                "title": .contains("oven"),
                "due": .resolvedDate(.relative(seconds: 20 * 60), toleranceSeconds: 120),
            ])],
            note: """
            Duration-shaped phrasing that must NOT become set_timer, and that requires \
            adding to the current time rather than reading a clock face.
            """
        ),
        EvalCase(
            id: "date-calendar-next-monday-3pm",
            transcript: "Block out three o'clock next Monday for the design review",
            caseClass: .dateExtraction,
            expected: [ExpectedCall("create_calendar_event", [
                "title": .contains("design review"),
                "start": .resolvedDateAnyOf(
                    [
                        .wallClock(dayOffset: 5, hour: 15, minute: 0),   // Mon 8/24
                        .wallClock(dayOffset: 12, hour: 15, minute: 0),  // Mon 8/31
                    ],
                    toleranceSeconds: 60
                ),
            ])],
            note: """
            \"Next Monday\" is genuinely bi-modal for humans, so both readings pass — but \
            3pm rather than 3am is not optional.
            """
        ),
        EvalCase(
            id: "date-calendar-30-minute-call",
            transcript: "Put a thirty minute call with Alex on my calendar at four today",
            caseClass: .dateExtraction,
            expected: [ExpectedCall("create_calendar_event", [
                "title": .contains("alex"),
                "start": .resolvedDate(.wallClock(dayOffset: 0, hour: 16, minute: 0)),
                "duration_minutes": .number(30),
            ])],
            note: "Duration and start time in one sentence; \"four\" must read as 16:00."
        ),
        EvalCase(
            id: "date-calendar-tomorrow-830",
            transcript: "Coffee with Priya tomorrow at eight thirty in the morning",
            caseClass: .dateExtraction,
            expected: [ExpectedCall("create_calendar_event", [
                "title": .contains("priya"),
                "start": .resolvedDate(.wallClock(dayOffset: 1, hour: 8, minute: 30)),
            ])],
            note: "Non-o'clock minutes, which small models love to round to :00."
        ),
        EvalCase(
            id: "date-reminder-no-time",
            transcript: "Remind me to buy milk",
            caseClass: .dateExtraction,
            expected: [ExpectedCall("create_reminder", [
                "title": .contains("milk"),
                "due": .absent,
            ])],
            note: """
            The inverse failure: no time was given, so inventing a due date is wrong. \
            `due` is optional in the schema and the model must leave it out.
            """
        ),
        EvalCase(
            id: "date-reminder-day-after-tomorrow",
            transcript: "Remind me to send the invoice the day after tomorrow at ten in the morning",
            caseClass: .dateExtraction,
            expected: [ExpectedCall("create_reminder", [
                "title": .contains("invoice"),
                "due": .resolvedDate(.wallClock(dayOffset: 2, hour: 10, minute: 0)),
            ])],
            note: "Two-step relative offset — the arithmetic small models most often drop."
        ),
    ]

    // MARK: - Negative (8)

    /// `.pass` means no tool fired. The old suite had none of these, so the failure mode
    /// that actually costs a user something — a spurious calendar write — was unmeasurable.
    public static let negative: [EvalCase] = [
        EvalCase(
            id: "negative-capital-of-france",
            transcript: "What's the capital of France?",
            caseClass: .negative
        ),
        EvalCase(
            id: "negative-small-talk",
            transcript: "How's your day going?",
            caseClass: .negative
        ),
        EvalCase(
            id: "negative-thanks",
            transcript: "Thanks, that's all for now",
            caseClass: .negative,
            note: "A closing pleasantry; some models answer it with run_shortcut."
        ),
        EvalCase(
            id: "negative-minutes-in-a-day",
            transcript: "How many minutes are there in a day?",
            caseClass: .negative,
            note: "Bait for set_timer: the sentence contains a duration but asks for a fact."
        ),
        EvalCase(
            id: "negative-what-time-is-it",
            transcript: "What time is it right now?",
            caseClass: .negative,
            note: """
            Answerable from the injected current-time line. A tool call here means the model \
            didn't read its own context.
            """
        ),
        EvalCase(
            id: "negative-capability-question",
            transcript: "Can you actually see my calendar?",
            caseClass: .negative,
            note: "A question *about* a capability, not a request to use it — bait for read_next_events."
        ),
        EvalCase(
            id: "negative-joke",
            transcript: "Tell me a joke about penguins",
            caseClass: .negative
        ),
        EvalCase(
            id: "negative-explain-acronym",
            transcript: "What does the acronym API stand for?",
            caseClass: .negative
        ),
    ]

    // MARK: - Multi-step (4)

    /// Run through the real agent loop against stub tools. `call_number`'s own description
    /// tells the model to call `find_contact` first; until now that flow had never been
    /// evaluated even once.
    ///
    /// `EvalStubs.contactNumber` is what the stubbed `find_contact` returns, so the second
    /// step's `number` argument is checking genuine cross-step threading: the model can only
    /// produce it by reading step one's `<tool_response>`.
    public static let multiStep: [EvalCase] = [
        EvalCase(
            id: "multi-call-dave",
            transcript: "Call Dave",
            caseClass: .multiStep,
            expected: [
                ExpectedCall("find_contact", ["name": .contains("dave")]),
                ExpectedCall("call_number", ["number": .digits(EvalStubs.contactNumber)]),
            ],
            orderMatters: true
        ),
        EvalCase(
            id: "multi-call-mom",
            transcript: "Give my mom a ring",
            caseClass: .multiStep,
            expected: [
                ExpectedCall("find_contact", ["name": .contains("mom")]),
                ExpectedCall("call_number", ["number": .digits(EvalStubs.contactNumber)]),
            ],
            orderMatters: true,
            note: "Idiomatic phrasing for the same chain."
        ),
        EvalCase(
            id: "multi-text-sarah-late",
            transcript: "Text Sarah that I'm running about ten minutes late",
            caseClass: .multiStep,
            expected: [
                ExpectedCall("find_contact", ["name": .contains("sarah")]),
                ExpectedCall("compose_message", [
                    "number": .digits(EvalStubs.contactNumber),
                    "body": .contains("late"),
                ]),
            ],
            orderMatters: true
        ),
        EvalCase(
            id: "multi-lookup-then-call",
            transcript: "Find Dave's number and then call him",
            caseClass: .multiStep,
            expected: [
                ExpectedCall("find_contact", ["name": .contains("dave")]),
                ExpectedCall("call_number", ["number": .digits(EvalStubs.contactNumber)]),
            ],
            orderMatters: true,
            note: "The chain stated explicitly, as a difficulty floor for the two above."
        ),
    ]

    // MARK: - Ambiguity (5)

    /// The system prompt says "If the request is ambiguous, ask a short clarifying question
    /// instead of guessing." Nothing measured whether that instruction did anything.
    public static let ambiguity: [EvalCase] = [
        EvalCase(
            id: "ambiguous-remind-me-about-the-thing",
            transcript: "Remind me about the thing",
            caseClass: .ambiguity,
            requiresQuestion: true
        ),
        EvalCase(
            id: "ambiguous-set-a-timer",
            transcript: "Set a timer",
            caseClass: .ambiguity,
            requiresQuestion: true,
            note: "No duration. Guessing five minutes is a worse answer than asking."
        ),
        EvalCase(
            id: "ambiguous-put-it-on-my-calendar",
            transcript: "Put it on my calendar",
            caseClass: .ambiguity,
            requiresQuestion: true,
            note: "No title and no time — the two required arguments of create_calendar_event."
        ),
        EvalCase(
            id: "ambiguous-open-it",
            transcript: "Open it",
            caseClass: .ambiguity,
            requiresQuestion: true
        ),
        EvalCase(
            id: "ambiguous-text-her",
            transcript: "Text her that I'll be there",
            caseClass: .ambiguity,
            requiresQuestion: true,
            note: "Unresolvable pronoun; picking a contact would message the wrong person."
        ),
    ]

    // MARK: - Spurious extra (4)

    /// Exact call-count cases. The old harness scored `toolCalls.first` and threw the rest
    /// away, so a model that turned on the flashlight *and* created a reminder scored 1/1.
    public static let spuriousExtra: [EvalCase] = [
        EvalCase(
            id: "extra-flashlight-and-joke",
            transcript: "Turn on the flashlight and tell me a joke",
            caseClass: .spuriousExtra,
            expected: [ExpectedCall("toggle_flashlight", ["state": .caseInsensitive("on")])],
            note: "The joke is text, not a tool. Exactly one call."
        ),
        EvalCase(
            id: "extra-timer-and-weather",
            transcript: "Set a timer for five minutes, and what's the weather like out there?",
            caseClass: .spuriousExtra,
            expected: [ExpectedCall("set_timer", ["minutes": .number(5)])],
            note: "No weather tool exists; the model must decline that half in words."
        ),
        EvalCase(
            id: "extra-self-correction",
            transcript: "Set a timer for ten minutes — actually no, make it twenty",
            caseClass: .spuriousExtra,
            expected: [ExpectedCall("set_timer", ["minutes": .number(20)])],
            note: "Spoken self-correction. Two timers is the wrong answer; so is ten minutes."
        ),
        EvalCase(
            id: "extra-two-legitimate-calls",
            transcript: "What's on my calendar today, and remind me to water the plants",
            caseClass: .spuriousExtra,
            expected: [
                ExpectedCall("read_next_events"),
                ExpectedCall("create_reminder", ["title": .contains("plant"), "due": .absent]),
            ],
            note: """
            The control for this class: two calls are genuinely correct here, so an \
            over-strict "never more than one call" rule fails this case.
            """
        ),
    ]

    // MARK: - Workflow (5)

    /// Repetition is where a chat-shaped agent loop stops working: every hand-back costs a
    /// full generation over a prompt that just grew, and a small model loses its count
    /// somewhere around step four. These cases measure whether the model reaches for
    /// `repeat_steps` — and, just as importantly, whether it stops reaching for it once
    /// the request is no longer repetitive.
    public static let workflow: [EvalCase] = [
        EvalCase(
            id: "workflow-blink-ten-then-call",
            transcript: "Toggle the light on and off then pause. Do this 10 times and then call 6316452763",
            caseClass: .workflow,
            expected: [
                ExpectedCall("repeat_steps", [
                    "steps": .contains("toggle_flashlight"),
                    "times": .number(10),
                ]),
                ExpectedCall("call_number", ["number": .digits("6316452763")]),
            ],
            orderMatters: true,
            note: """
            The motivating case. Done one call at a time this is 31 hand-backs; done right \
            it is two calls, and the loop budget never comes near its limit.
            """
        ),
        EvalCase(
            id: "workflow-blink-five",
            transcript: "Blink the flashlight five times",
            caseClass: .workflow,
            expected: [
                ExpectedCall("repeat_steps", [
                    "steps": .contains("toggle_flashlight"),
                    "times": .number(5),
                ]),
            ],
            note: "Spelled-out count: the number has to survive word-to-digit conversion."
        ),
        EvalCase(
            id: "workflow-pause-between-actions",
            transcript: "Turn the flashlight on, wait three seconds, then turn it off",
            caseClass: .workflow,
            expected: [
                ExpectedCall("repeat_steps", ["steps": .contains("wait")]),
            ],
            note: """
            Sequenced, not repeated. Scored on the workflow tool because the pause is the \
            point; a model that instead chains toggle → wait → toggle is doing something \
            defensible, and this case failing that way is worth reading as a tie, not a bug.
            """
        ),
        EvalCase(
            id: "workflow-single-action-no-repeat",
            transcript: "Turn on the flashlight",
            caseClass: .workflow,
            expected: [ExpectedCall("toggle_flashlight", ["state": .caseInsensitive("on")])],
            note: """
            The guard for this class. Adding a loop primitive gives every model a new way \
            to over-engineer one switch; this is the case that catches it.
            """
        ),
        EvalCase(
            id: "workflow-timer-not-repeat",
            transcript: "Set a timer for 10 minutes",
            caseClass: .workflow,
            expected: [ExpectedCall("set_timer", ["minutes": .number(10)])],
            note: """
            A "10" next to a duration, deliberately close to the phrasing of the repeat \
            cases. Catches a model that has learned "10 ⇒ repeat_steps".
            """
        ),
    ]
}

/// Fixed values the multi-step stubs return, so cross-step argument threading has one
/// correct answer that can be asserted.
public enum EvalStubs {
    public static let contactName = "Dave Okafor"
    public static let contactNumber = "+1 (415) 555-0147"

    /// What the stubbed `find_contact` hands back — same shape as `ContactsTool`'s real
    /// result string, because that string is the model's only source for step two.
    public static func findContactResult(name: String) -> String {
        let resolved = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(resolved.isEmpty ? contactName : resolved) — mobile: \(contactNumber)"
    }
}
