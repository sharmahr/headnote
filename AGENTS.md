# AGENTS.md

Ground rules for every agent and reviewer in this repository.

**Source of truth:** the frozen design, SOLUTION.md v3.3, kept outside this repo at `../report-memory-layer/solution/SOLUTION.md`. Every `§` below refers to it. Don't redesign. If the spec looks ambiguous or wrong, stop and ask the maintainer rather than choosing an interpretation.

## 1. The spec is the request

- Everything in the spec counts as explicitly requested: its features, its stack (§8, pinned versions included) and its test policy (§11, §14.2–14.4).
- Ponytail, and any other simplification or YAGNI review, decides **how** to build a spec item, never **whether** to build it. Only §14.5's cut order removes a spec item, and only the maintainer invokes it.
- Slices land in §14.2 order: S0, then S1, and so on.
- Tests come first. Use proptest for parsers and for the rules on stale notes (validation and relocation, §6.2–6.3) and note authority (`authorize()`, §6.1). Core logic gets mutation testing.
- Rust follows `.github/skills/rust-best-practices/`. MCP code uses the rmcp SDK (§8.2).
- Never fake a real-host check, and never report a measurement that wasn't run. Without the host, platform, credentials or keys, the result is **Not run** (§11.1). No mock host and no Tier A replay stands in for a real-host gate (§14.2).
- Commit messages cite the spec sections they implement.

## 2. Deliberate no-ops on timeout: don't "fix" these

Headnote fails open for delivery and closed for privacy (§2.1 principle 6, §6). Running out of the event deadline gives the host the per-event no-op. Running out of a sub-budget drops only that step (no receipt, notes left unwitnessed or withheld, a brief from an older index) and the answer otherwise proceeds. Both are the design. Don't add retries, waits, longer timeouts, fallbacks (never a `git` subprocess, §6.15), error output to the host or defaults.

| Where | On timeout | § |
|---|---|---|
| Supervisor deadline: one monotonic budget from launcher entry, 150 ms for tool and prompt hooks, 500 ms for start, compact and stop; each blocking step gets what remains, less a 5 ms margin kept for the no-op | Kill the worker's process group, write the per-event compiled-in no-op **first**, then try one nonblocking ≤256 B error append (HN-E101); an unfinished append is abandoned. The answer never waits on recording. | §4.2, §7.2 |
| Reading host input | Input still arriving at the deadline: no-op, HN-E101. | §7.2 |
| Index unreadable or behind | Unreadable (HN-E102): tool hooks deliver nothing and never deny until a generation is published; the brief and `recall` scan `store.sqlite` and the team tree directly, ≤500 notes and ≤200 ms, and a scan cut by either limit withholds every note group (`INDEX_LAG`). Behind: ≤64 changed team-note blobs are read at use; a larger or incomplete delta withholds every note group until the refresh. | §4.5, §4.6, §6.14 |
| Validation | Candidates not evaluated by the deadline are `withheld`, reason `DEADLINE`; "no packet by the deadline" is never "validated". A predicate that hits its 5 ms cap or the deadline reads UNKNOWN. An incomplete sweep reads UNKNOWN: nothing is declared unique, absent, MOVED or GONE by inference. | §4.5, §6.2, §6.3, §6.5 |
| Deny rules | A check that is over its cap or unfinished allows the call, counted "uncheckable", never "prevented"; so do an UNKNOWN, CHANGED or AMBIGUOUS note, an unreadable anchor, an I/O error and a failed reservation. A spent 4 KB rule-reason pool allows the call as `RULE_BUDGET`. A `git push` without an effective pin is allowed as "content-uncheckable". | §6.12 |
| Reservation in `store.sqlite` | `busy_timeout` = min(remaining − 5 ms, 50 ms). Busy past it: the call is allowed with no packet, knock or deny (HN-E118). A hook transaction that runs out of budget emits nothing (`DEADLINE`). | §4.6, §6.5 |
| Growers waiting on `grow.lock` | Budget spent: a counted no-op or refusal (HN-E111). `grow.lock` is never awaited inside an open transaction. | §4.6 |
| CLI commands | Wait ≤1 s for `store.sqlite` and `grow.lock`, then exit busy (exit 4). | §4.6, §10.5 |
| Purge fence and the answer write | The fence is taken only within the remaining budget. A late fence or failed check: the hook answers its no-op, or the append is skipped, counted. Output that may have been written is never resent or re-knocked; the charge stays. | §6.5, §6.15, §7.2 |
| `headnote purge` | Step 1 takes its locks only within the longest hook budget. If one isn't held in time, purge releases every lock, changes nothing and reports "not started", naming the holders; running it again retries. | §6.15, §10.1 |
| Intake append | Locks use `LOCK_NB`, polled for ≤2 ms. Busy or out of budget: skipped, counted by one in-place 8 B `pwrite`. A lost count is accepted; counts are a lower bound. | §7.2 |
| Landing witnesses | At most 16 unwitnessed notes are checked within the deadline; the rest stay unwitnessed. | §6.1 |
| Snapshot digests for test commands | Capped at 100 ms from the same budget. If one doesn't fit, the run gets no receipt; the answer doesn't wait. | §6.10, §8.3 |
| Post worker | 1 s `setitimer` alarm with `SIGALRM`'s default action, and `RLIMIT_CPU` 1 s past use (a job object and waitable timer on Windows). No free slot of 4: an HN-E115 gap line if appendable, then exit at once. A result too large to redact and parse in time keeps only its size and a gap marker, and gets no receipt. | §7.2, §8.3 |
| Maintenance slices | Start and stop hooks spend ≤300 ms on them before answering. A killed slice loses at most its own progress. | §4.2 |
| Host-owned 2 s timeout: Claude Code `timeout: 2`, Codex 2 s, Copilot `timeoutSec: 2`, Cursor `timeout: 2`, Gemini `timeout: 2000` | Reached only if the supervisor hangs; the host decides. On Copilot a killed pre hook denies that one call, an accepted residual. | §7.1, §7.2 |

**The no-op is a compiled-in constant per event** (§7.1, §7.2). Claude Code, Codex and Copilot: empty stdout, exit 0. Cursor permission hooks: zero bytes, exit 1; other Cursor events: `{}`, exit 0. Gemini: `{}`, exit 0. Never `{"permission":"allow"}`. Hooks write nothing to stderr on Gemini or Copilot (§7.2). Elsewhere, debug output goes to stderr only with `HEADNOTE_DEBUG=1`; headless and CI user-only output goes to stderr and, when set, `$GITHUB_STEP_SUMMARY` (§7.1).

**Same rule, other triggers.** These are no-ops by design too: host input that is invalid, unrecognised or over 16 MB (HN-E104); a worker that fails verification or is outside the accepted ABI range (HN-E113); a worker crash, abort, signal or bad answer (HN-E112); `purge.active` at launcher entry; an unknown host build or schema fingerprint, which gets `pull` only (HN-E105); a full disk, read-only store or exhausted ledger reserve (HN-E118); the intake caps (1 MB per log, 32 logs); a duplicate instance (§7.3); a missing launcher mid-swap on Windows (§8.5).

**Privacy fails closed.** If redaction is unavailable or faults (HN-E107), nothing is written, exported, sent or content-hashed, and hooks allow every call (§6.15). Never "recover" by writing unredacted text.

## 3. Done means `just check` passes

Work is done only when `just check` passes, locally and in CI. It runs the formatter check (`cargo fmt --all --check`), `cargo clippy` with `-D warnings`, and every test; the `justfile` holds the exact commands. Don't reach green by weakening the gate (silencing lints, ignoring or deleting tests, shrinking proptest cases); fix the cause.
