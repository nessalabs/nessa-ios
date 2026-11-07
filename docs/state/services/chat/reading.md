---
id: "chat-reading"
title: "Read replies and react"
kind: "feature"
status: "implemented"
summary: "Transcript presentation, quoted replies and local reactions have different persistence boundaries."
parent: "chat"
sources:
  [
    "Sources/NessaFeatures/Presentation/Pages/NessaThreadView.swift",
    "Sources/NessaFeatures/Presentation/Pages/ThreadScrollMetrics.swift",
    "Sources/NessaFeatures/Presentation/Composites/MessageContextOverlay.swift",
    "Sources/NessaFeatures/Presentation/Composites/ReplyThreadView.swift",
    "Sources/NessaFeatures/Domain/MessageReply.swift",
    "Sources/NessaFeatures/Domain/ConversationReplies.swift",
    "Sources/NessaFeatures/Presentation/ViewModels/MessagesViewModel.swift",
  ]
sourceRevision: "8a027f07ecc1b27fb63502852648cb467e308720"
diagramLinks: {}
---

# Read replies and keep local reactions

The thread displays streamed conversation replacements, typing indicators and
message artifacts. Long-press a message to react, reply or copy. Reply inserts
quoted context into the outgoing text; the current gateway does not receive a
separate universal reply-graph command. The phone retains local reply links so it
can group known turns for this connection.

A reaction is a local preference keyed by conversation and stable message ID.
Tapping the same emoji removes it; another emoji replaces it. These marks are not
sent to the gateway or synchronized to another phone. Unread, mute and pin choices
are also local preferences. The pin policy keeps at most three distinct IDs.
Mute does not configure remote push notifications, which are not implemented.

The scroll view tracks whether the reader is near the newest content and offers
Jump to latest. Bottom geometry subtracts visible container height and top inset;
it does not add the bottom inset again. Photo stacks and full-screen viewers own
their horizontal gestures, while navigation preserves back gestures. Reduce
Motion affects typing and transition animations. These are presentation concerns,
not remote message-ordering guarantees.

Markdown renders text into the app's message components. File artifacts show
original metadata rather than pretending there is a local executable path.
[Media](../media/README.md) explains why a remote photo can have an unavailable
placeholder even when its message exists.

Source and Swift tests cover reply projection, preferences, markdown blocks,
scroll arithmetic and photo swipe decisions. The current run did not exercise
a simulator's gestures, VoiceOver or visual layout. No TLA proof is claimed for
these presentation contracts.
