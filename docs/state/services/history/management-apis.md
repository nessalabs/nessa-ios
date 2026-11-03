---
id: "history-management"
title: "Management APIs and screens"
kind: "feature"
status: "implemented"
summary: "Several durable management owners are implemented without being exposed as normal app controls."
parent: "history"
sources:
  [
    "Sources/NessaFeatures/Application/PhoneConversationSharing.swift",
    "Sources/NessaFeatures/Application/PhoneConversationDeletion.swift",
    "Sources/NessaFeatures/Application/PhoneOwnerApprovalJournal.swift",
    "Sources/NessaFeatures/Composition/NessaDependencies.swift",
    "Sources/NessaFeatures/Presentation/Pages/NessaConnectionView.swift",
    "Sources/NessaFeatures/Presentation/ViewModels/MessagesViewModel.swift",
  ]
sourceRevision: "8a027f07ecc1b27fb63502852648cb467e308720"
diagramLinks: {}
---

# Distinguish management APIs from screen actions

This repository contains lower-level management APIs in addition to its current
phone screens. Their tests establish their own behavior; they do not mean the
app offers every operation. Use this page when integrating those APIs, not as a
list of buttons to find in Settings.

| API                           | What it owns                                                               | Current entry-point boundary                                                             |
| ----------------------------- | -------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| Conversation sharing          | Saved exact share intent, current owner/device correlation, acknowledgment | Injected into view model; technical per-chat sharing controls are absent from normal UI. |
| Durable conversation deletion | Saved deletion identity, Check/Retry, receipt observation                  | Constructed in container, not injected into normal MessagesViewModel deletion flow.      |
| Owner approval preparation    | Reservation and native preparation facts                                   | Standalone journal; cannot select, authorize or connect a phone.                         |

Sharing re-observes active pairing and matches owner, profile, credential and
receiver before asking for read access. A lost reply leaves the saved intent for
explicit Check/Retry. A grant acknowledgment does not prove that native retained
history is readable. Hiding old per-chat controls does not expand the gateway's
actual authorization contract to all future chats.

Durable deletion saves its request before sending and rejects another unresolved
intent for the same conversation. Check observes; Retry uses the original saved
identity. It validates the response's authenticated source and request ID. A
valid historical receipt is saved to its original store even if the UI becomes
obsolete, then current-context checks decide whether to return success to that
UI. Applied acknowledgment, absence, a deletion fence and retained tombstones
are distinct evidence. [Swipe deletion](../chat/archive-delete.md) uses a different
current route and cannot inherit these durable recovery claims.

Owner approval preparation keeps at most 64 records by default, rejects duplicate
reservation identities and waits for owned publication during close. It records
preparation only; it does not make the phone authorized. A cancelled observer
cannot abandon its admitted operation's factual publication.

All three have Swift unit/fixture coverage in the recorded run. No direct model
is attached: these APIs need their own source-specific future model review rather
than borrowing a nearby send or profile model as full coverage.
