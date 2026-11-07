# Independent source and model review

Parent reviewer, separate from the atlas author and the docs-only reader agent.
Reviewed critical chat, pairing, deletion, profile, history and dictation claims
against production sources at `8a027f07ecc1b27fb63502852648cb467e308720`, plus all
eight model specs/configs and their persisted control definitions.

## Findings closed

P1 (P2 severity): the first pairing explanation said cancellation before the local
save prevents retaining a link. Source checks cancellation before awaiting the
old-record load and new save. A later cancellation can occur before actual saving
and still produce a saved link. The page now states the precise observation point,
shows save failure without implying remote revocation, and keeps the completed
link after a late cancellation. Rechecked against DesktopLinking.link.

P2 (P3 severity): dictation cancellation needed its visible effect explained. Source
invalidates future callbacks but does not erase the transcript or text already
copied into the composer. The page now separates cancel during permission request,
finish during listening and lifecycle cancellation; existing text/items are not
presented as rolled back. Rechecked against DictationViewModel and composer use.

M1 (P2 severity): the original recovery negative control changed the send count
and an independent failure flag together. An actual send-only defect could evade
the invariant. The final OutboxRecovery captures the real count before and after
Recover, asserts equality, and mutates only the sends assignment. Inspected the
updated spec and control; the saved counterexample shows the intended extra send.
Final baseline/control rerun recorded eight passing models and seventeen expected
semantic failures, with no unchecked rules.

## Other checked boundaries

- Live PhoneProductChat/outbox admission is separate from the alternative native
  retained-history commandReady predicate. Cached readability does not by itself
  establish authority, and the docs do not claim every live send uses that predicate.
- Unknown retained delivery can cause acceptance of an unchanged composer draft;
  captured revision/scope matching protects later edits without proving remote
  completion. Model properties record the actual revision and scope used to clear.
- Normal delete calls MessagingService.delete and uses exact follow-up evidence
  or native display refresh; it is not the separate durable deletion actor.
  Account generation fences results, and inbox absence is not deletion proof.
- ProfilePreparation publishes the preparing registry successfully before credential
  effects, then publishes prepared metadata. Visible readback alone is insufficient.
- Retained history validates profile/registry identity and page receiver/generation;
  model claims intentionally omit cursor, quotas, native storage and transcript grammar.
- Journal first-refusal and acknowledgment matching are distinct guards. The model
  represents one pending command and explicitly excludes storage leases/concurrency.
- Linked retirement guards physical deletion by reader drain and clean close;
  the model does not turn local Forget into remote revocation or network approval.
- Subscription controls challenge cancelled activation and loss of the late ID;
  dictation controls challenge captured-token checks on results and cleanup.

These models use independent captured facts rather than treating a desired final
phase as proof of every prerequisite. They remain small abstractions; they do not
establish complete protocol correctness, actual remote effects or liveness.

## Decision

Pass for this sampled source-fidelity and eight-model review scope. No unresolved
material finding above remains. The separate reader retest must close its findings
before publication. Author-executed Swift/browser/model evidence is explicitly
scoped in the verification page; this reviewer inspected results and source but
did not independently rerun all 425 Swift tests. This is not a human usability
study, full audit of every implementation line or automatic model/code equivalence.
