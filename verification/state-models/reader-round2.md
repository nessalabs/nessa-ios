# iOS docs-only reader retest, round 2

Read revised delivery, dictation, attachments and verification Markdown only. No implementation or TLA source consulted. Rechecked the two unresolved tasks and current evidence navigation.

## Task 2: switch desktop while cached chats exist

Resolved. Delivery now says replacement clears old chat/view collections and returns Home; re-pairing has a different cache scope. The reader must open a conversation provided by the current connection rather than reuse old screen identity. The new section lists connected-current-session, revocation, setup, pending-load/submission and composer blockers, while distinguishing local admission from gateway refusal. It explicitly avoids applying the alternative history commandReady predicate. No inference from cached display to authority is required.

Supporting sentences: “an old cached conversation is not permission to address it on the new Mac” and “These local conditions permit an attempt; the gateway may still refuse the conversation or action.”

## Task 5: cancel attachment preparation or dictation

Resolved. Dictation distinguishes tapping during permission/start (cancel) from tapping while listening (finish); finishing is busy/disabled and there is no separate active-stream Cancel button. Leaving composer/background or qualifying inactive transitions cancels. Already copied recognized text remains, and dictation never submits it.

Attachments now distinguishes cancelling selection without an item, removing one local tray item before sending, leaving composer during preparation, and failure after some uploads. Existing items are not cleared by picker/preparation cancellation; a cancelled preparation cannot append its late item. Removal is disabled during send and is not a remote delete. The explicit screen-destruction caveat avoids a new persistence promise across navigation/restart.

Supporting sentences: “Cancelling does not erase text already recognized” and “Removing a draft item is not a remote-delete command.” Reader can choose the correct stage without inventing rollback.

## Evidence and drill-down

Root's verification link reaches an explicit 425 Swift Testing baseline, 29-page/8-model/17-invariant/17-control current result, clickable control/results/review/browser artifacts, and separate device/native-fixture/cloud exclusions. It distinguishes the zero-test XCTest wrapper from the actual Swift Testing count and renderer screenshots from phone UI verification. The “final reader retest pending” sentence is now stale and can be replaced with this retest result after author records it.

Delivery and dictation now have selective diagramDetails explaining Unknown/Departed/Idle; attachment details explain uploaded-without-submission and refusal. This pass checked authored bindings and text, not live browser interaction; parent separately exercised inspectors.

## Verdict

The material reader gaps from tasks 2 and 5 are closed in the reviewed text. Tasks 1/3/4 were already answerable in round 1. No unresolved material misunderstanding remains in these five sampled journeys. This is simulated reader evidence, not all-page certification, source fidelity proof or physical-iPhone qualification.
