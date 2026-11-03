# iOS docs-only reader review, round 1

Read only `docs/state` Markdown from root. No Swift implementation, tests, TLA specs, or author coaching was consulted before recording these answers. Intended reader understands basic software concepts but is new to Nessa. The exercise checks supported decisions, not whether every API is implementable from prose alone.

## 1. Send, connection drops, can I retry?

Path: README -> services/chat/README -> delivery; followed draft for clearing behavior.

Supported answer: a missed reply is uncertain, not proof that sending failed. The live outbox keeps exact request/turn/conversation/text/uploaded refs; Retry uses that saved request rather than current composer. Reconnect only checks receipts and never resends automatically. If the row offers Retry for absent/lookup-failed evidence, Retry checks again and resends only if absent. Attempt-observed/unresolved uncertainty offers no Retry. Accepted/running/done are different gateway stages. The composer can clear even when unknown is retained, while later edits are protected.

Supporting text: "Retry uses that exact saved request, not the current message field"; "Restart/reconnect recovery only looks up uncertain records; it never replays sends"; outcome table distinguishes whether Retry is offered.

Useful: concrete “Summarize this file” scenario, compact outcome/action table, explicit foreground three-send versus restart behavior, scoped model excludes foreground policy.

No material guessing needed for the Retry decision. “Receipt” is understandable as gateway evidence through context, though one short local definition would help. The chart is intentionally narrower than full foreground behavior and says so.

## 2. Switch desktop with cached chats, can I send?

Path: README -> connection -> session/pairing; README -> history -> retained/snapshot; delivery for current live path.

Supported answer: cached display alone cannot authorize a send. Current live product outbox uses the current product connection, not the alternative profile-backed commandReady predicate. Old connection generations cannot publish into current UI; scopes include address/credential/instance or pairing identity, and re-pairing changes local cache scope. Do not infer remote access from seeing old content.

Supporting text: history opening says "A disconnected screen can show saved conversation content without being allowed to send"; session says "Results from an older generation cannot publish into the current screen" and "Re-pairing starts a different local cache scope."

Remaining reader gap: delivery references the outbox route's different admission checks but does not enumerate them as a short user-facing decision. A reader can safely conclude “cache is insufficient,” but cannot determine exactly when the Send control becomes available after replacement or whether an old displayed conversation is usable on the new desktop. Add a source-checked sentence/condition for the normal screen, or state that old cached conversation visibility does not imply it can be addressed on the replacement. Do not substitute the alternative commandReady rule.

## 3. Swipe Delete then restart: what is durable?

Path: README direct Archive and delete -> management APIs only to distinguish standalone implementation.

Supported answer: normal swipe temporarily hides pending rows and sends a remote delete; UI absence does not prove remote deletion. Confirmed success removes local marks/cached view/snapshot. Error refreshes and on the legacy path exact not-found may permit cleanup; uncertain reads preserve data. Dismissing the screen does not undo an admitted delete. No normal-screen uncertain-delete restart recovery is promised. The standalone PhoneConversationDeletion API has durable intent/Check/Retry but is not injected into normal swipe.

Supporting text: "There is no normal-screen restart recovery procedure for uncertain deletion promised by this atlas" and "its tests do not establish that swipe-delete uses a durable deletion journal."

This accurately supports an “unknown after restart” answer instead of inventing a retry. It would be slightly clearer to say directly whether the optimistic pending-hidden flag itself is in-memory, but the crucial distinction is already explicit. The diagram's Rechecking -> Removed edge names the exact legacy not-found requirement.

## 4. Forget desktop: does remote access end?

Path: README -> connection -> pairing.

Supported answer: no. Forget removes the local link, blocks new reads, drains admitted readers and deletes private directory only when cleanup permits. Failed close can retain the directory. To revoke remote access, use desktop Settings -> Linked devices. Cancellation racing local save may retain the link; a storage failure does not revoke remote approval.

Supporting text: "To revoke remote access, use the desktop's Settings → Linked devices; local Forget is not revocation."

This task has a clear answer and safe next action without implementation knowledge.

## 5. Add attachment / dictate, then cancel: what remains?

Path: README -> media -> attachments/dictation; delivery and draft for send boundaries.

Supported attachment answer: selecting a file/photo prepares a draft; it does not submit to an agent. Send uploads bytes first, then saves send identity. Upload failure or scope replacement may leave previously uploaded bytes without a message; no all-or-nothing rollback is promised. Physical camera/picker, remote upload and provider support are explicitly not verified by the Swift tests.

Supported dictation answer: it fills text rather than sends audio; tap waveform again finishes recognition, then review and separately Send. Cancelling rotates a speech-session token, so old callbacks cannot replace a newer transcript. Stream end without final text is an error, not invented success.

Remaining reader gap: the task asks what remains _after cancellation_. Dictation page never says whether already recognized/inserted composer text remains or is cleared when cancelled; token fencing only explains future callbacks. It also does not identify a user-accessible Cancel gesture versus internal lifecycle cancellation. Attachment page describes upload failure/scope replacement but not cancellation/removing a selected draft item or cancelling the picker, so local draft and uploaded-byte fate cannot be inferred as one rule. Add the actual UI-supported cancellation/remove behavior and distinguish stages, without promising remote deletion. If no explicit Cancel control exists, say which UI action finishes and which lifecycle event cancels.

## Cross-cutting observations

Task navigation and simple opening scenarios are strong. Reachable screen behavior is explicitly separated from standalone profile/deletion APIs. Current live outbox and alternative retained-history authority are kept separate; this prevents a major misleading simplification.

The files sampled have `diagramLinks: {}` and no `diagramDetails` on their consequential states. In the renderer's diagram-only mode, Unknown/Removed/Forgotten/Idle therefore lack authored drill-down explanations for the exact uncertainty described in prose. This review did not run the browser; it is a metadata observation. Consider selective details for unknown delivery, pending/removed deletion, local forget, and dictation cancellation. Avoid putting every technical paragraph on every node.

Long frontmatter titles such as “Send a message and recover uncertain delivery” or “Prepare and upload a photo or file” can be shortened for navigation while retaining descriptive H1s; verify actual truncation in browser before changing.

## Verdict

Tasks 1, 3 and 4 are answerable with concrete evidence and limits. Task 2 yields the safe negative rule but lacks the normal-screen transition to send-ready after replacement. Task 5 lacks cancellation's effect on already prepared draft/text and how the user invokes it. Require source-aware clarification of those two behavioral questions, then rerun these tasks. This sampled exercise does not establish every page's quality and does not claim real-user research or implementation correctness.
