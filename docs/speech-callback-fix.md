# Speech callback isolation fix

Crash F4121963-DEC7-4DFD-91F7-D8F14EB65EB2 reports a Swift actor assertion in the
speech authorization completion on Apple's background TCC queue. The original
closure was created inside MainActor-isolated start(), but this legacy API does
not guarantee main-queue delivery.

| Callback/order | Required owner |
| --- | --- |
| Permission answer on an arbitrary queue | Explicitly Sendable continuation relay; actor resumes its async start after await |
| User cancels while permission remains pending | Existing captured token/cancellation check refuses starting the obsolete recording |
| Audio tap on its audio thread | Explicit Sendable callback appends to its captured SDK request; no UI/actor state access |
| Recognition result/error on arbitrary queue | Explicit Sendable callback copies text/final/failure values, then hops to MainActor and checks token |
| Late recognition after cancel/new recording | Existing token fence drops it before draft/state mutation |

Background authorization regressions use a deliberately legacy non-Sendable block
signature, testing both granted and denied replies from a global dispatch queue.
The iOS SDK adapter and simulator waveform path must also build/run, because the
macOS transcriber fallback alone never compiles those Apple callback call sites.

Verification: 121 package tests, architecture/design-system checks and the iOS
simulator build passed. Independent implementation review found no actionable
issues. An intentional `MainActor.assumeIsolated` mutation in the relay crashed
the background-completion test with the same queue assertion; the source was
restored and checks passed. Removing only the Sendable annotation did not make
the host test fail, so it is not claimed as an annotation-specific regression.

The final build was installed and exercised in live mode on iOS 26.5. The
permission/recognition path kept Nessa open, returned a recognition-error alert,
and allowed return to the chat and waveform. The simulator's recognition failure
has not yet been diagnosed; a spoken transcript and physical-device recording
remain unverified.
