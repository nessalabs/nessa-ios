# Model and reader review

Source reviewed: `8a027f07ecc1b27fb63502852648cb467e308720`.
The author traced app composition and source before writing this atlas. A separate
parent reviewer checked source fidelity and the eight models. A separate
reader-review agent used only the docs before recording its answers. This is a
simulated newcomer exercise, not a real-user study. The
[independent technical review](independent-technical-review.md) records the
source checks, model challenge and final dispositions.

## Adversarial model review

The models deliberately cover selected rules, not all behavior of their pages.
Every control changes a guard or actual transition while retaining the semantic
invariant. All seventeen counterexample paths were inspected: each shows the
intended wrong revision, identity, publication order, reader cleanup or send count.

| Model                    | Bound                                                        | Claims exercised by controls                                                      |
| ------------------------ | ------------------------------------------------------------ | --------------------------------------------------------------------------------- |
| DraftOwnership           | One captured attempt, one edit, one scope replacement        | Clearing later revision; clearing replacement scope                               |
| OutboxRecovery           | One persisted request, at most two sends                     | Dispatch before durable departure; recovery changing actual send count            |
| JournalRefusal           | One command, attempts saturated at two                       | Later refusal removing uncertain command; foreign acknowledgment removing command |
| LinkedRetirement         | At most two readers, one forgetting                          | Delete before readers drain; delete after unclean close                           |
| SubscriptionCancellation | One pending server registration                              | Activate cancelled caller; lose returned late ID cleanup                          |
| HistoryCorrelation       | Two pages, two values per profile/receiver/generation        | Publishing each independent mismatch                                              |
| ProfilePreparation       | One preparing registry, visible/unconfirmed or durable write | Credential before durable preparation; prepared before credential                 |
| DictationGeneration      | One old callback, one replacement token                      | Stale transcript publication; stale cleanup resetting replacement                 |

M1 (corrected): the initial recovery property used an injected violation flag,
so a mutant changing only the send count could evade it. The final model records
the real send count before and after Recover and asserts equality. The mutant
changes only `sends'`, not a separate failure flag or invariant. Its counterexample
shows one send before recovery and two afterward. The complete final corpus was
rerun: eight baselines passed seventeen configured invariants; all seventeen
controls broke their expected invariant, with no unchecked rule. Aggregate
independent states: 90. See [results.json](results.json) for exact model digests,
checker version, dates and paths.

Finite models omit liveness, counter overflow, arbitrary concurrency, actual
storage/Keychain failure semantics and remote platform behavior where named in
the owning pages. No control demonstrates executable Swift or Rust conformance.

## Technical prose review

- Corrected pairing cancellation wording: only cancellation observed at the
  explicit pre-save check prevents saving; cancellation later can still precede
  or race a successful save. Added storage failure branch without implying
  remote approval rollback.
- Confirmed normal live sends use PhoneProductChat and its outbox. Native-history
  commandReady governs an alternate route, not every current live Send.
- Confirmed normal swipe deletion does not use the separately constructed durable
  deletion actor. No screen recovery claim is borrowed from standalone API tests.
- Confirmed unknown but retained outbox delivery can clear an unchanged composer.
  Draft revision/scope matching protects later edits, not remote completion.
- Confirmed cancelling dictation does not erase already copied text. The composer
  button cancels requesting but finishes listening; lifecycle cancellation is
  separate from a hypothetical Cancel button.

## Reader tasks and corrections

The independent reader followed root navigation for: uncertain send/Retry;
replacement desktop with cached chats; swipe delete then restart; Forget versus
revocation; attachment/dictation cancellation. Send, delete and Forget decisions
were answerable in round one. Two questions needed source-backed clarification:

1. The normal Send conditions after connection replacement were absent. Added
   the actual live-route conditions and explained old views/navigation are reset;
   local eligibility still does not override gateway refusal.
2. Cancellation explained stale callbacks but not existing text/items or available
   controls. Added requesting versus listening button behavior, lifecycle cancel,
   preserved draft text/tray, picker cancel, local remove and preparation cancel.
   No draft persistence or uploaded-byte rollback is promised.

Added a short receipt definition and in-memory pending-delete explanation. Added
selective diagramDetails so unknown delivery, deletion, profile failure, local
Forget, draft ownership and other consequential outcomes are readable from the
normal diagram view. [Round one](reader-round1.md) preserves the original reader
findings; [round two](reader-round2.md) re-ran the affected tasks and found no
material missing decision or unsupported claim in that sample. The reviewer
read only docs until recording answers. This does not establish every page’s
quality or implementation correctness.

## Execution and rendering

The original source baseline ran `./scripts/verify.sh`: architecture/design-system
checks, Swift build and 425 Swift Testing tests in two suites passed on arm64
macOS. Browser render evidence is in [browser-results.json](browser-results.json).
App simulator/device/live gateway checks remain explicitly unrun. Formatting
and canonical catalog validation are separate from both implementation tests
and reader understanding.
