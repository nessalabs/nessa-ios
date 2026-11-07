---
id: "chat"
title: "Chat and delivery"
kind: "service"
status: "implemented"
summary: "Follow the draft, the saved request and the gateway outcome separately."
parent: "nessa-ios"
sources:
  [
    "Sources/NessaFeatures/Presentation/ViewModels/MessagesViewModel.swift",
    "Sources/NessaFeatures/Application/MessagingService.swift",
    "Sources/NessaFeatures/Presentation/Pages/NessaThreadView.swift",
  ]
sourceRevision: "8a027f07ecc1b27fb63502852648cb467e308720"
diagramLinks: {}
---

# Chat and delivery

A chat displays the gateway's conversation and lets you prepare a local message.
The message field, the saved send request and the remote agent turn are different
things. Clearing the field does not by itself prove the remote agent finished.

- [Send and recover delivery](delivery.md): the current live outbox and its outcomes.
- [Keep a newer draft](draft.md): a delayed completion cannot clear later edits.
- [Recover journaled commands](journal.md): create and alternate send paths.
- [Stop the selected turn](stop.md): a saved Stop request is separate from completion.
- [Permission requests](permissions.md): read a review, choose its offered answer.
- [Replies, reactions and reading](reading.md): transcript behavior and local marks.
- [Archive and delete](archive-delete.md): remote action versus local disappearance.

The gateway owns actual agent execution and remote authorization. Phone tests
can check the requests and local outcomes without proving provider termination,
remote erasure or cross-device synchronization.
