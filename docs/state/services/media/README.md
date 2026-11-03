---
id: "media"
title: "Photos files and dictation"
kind: "service"
status: "implemented"
summary: "Import and upload finish before the message can reference content; dictation only fills the draft."
parent: "nessa-ios"
sources:
  [
    "Sources/NessaFeatures/Presentation/Composites/MessageComposer.swift",
    "Sources/NessaFeatures/Presentation/Composites/DraftAttachmentsTray.swift",
    "Sources/NessaFeatures/Application/AttachmentPolicy.swift",
    "Sources/NessaFeatures/Presentation/ViewModels/DictationViewModel.swift",
  ]
sourceRevision: "8a027f07ecc1b27fb63502852648cb467e308720"
diagramLinks: {}
---

# Send media or dictate a message

The plus menu offers Camera, Photos and Add Files. Each prepares a draft
attachment; Send later uploads it and includes its reference in a saved message.
The waveform starts speech recognition and writes text into the composer. It
does not record and send an audio attachment.

- [Prepare and upload attachments](attachments.md).
- [Display photos and file artifacts](display.md).
- [Start, finish or cancel dictation](dictation.md).

If preparation or upload fails, the send has not necessarily reached the same
stage as a delivery failure. [Delivery](../chat/delivery.md) explains the boundary:
bytes may already be uploaded while no send intent exists, or a saved send may
be uncertain after a missing reply.
