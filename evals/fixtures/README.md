# Judge fixtures

Hand-written completions with known-correct outcomes, used by CI.

**What this gates, precisely:** the scoring path — parser, matchers, contracts, report
writer, and the `ax-eval` CLI itself. If someone breaks the judge, these three cases stop
passing.

**What it cannot gate:** model behaviour. Recorded completions are frozen text, so a
change to the *prompt* cannot change them — the recording would still score the same while
the real assistant regressed. Catching that needs the model re-run against the suite, which
needs a GPU; GitHub-hosted runners have none. That job belongs to `swift run ax-eval` on a
Mac or the on-device eval screen, and its output belongs in `evals/` next to this file.

Stated plainly so nobody reads a green CI badge as "the assistant still works".
