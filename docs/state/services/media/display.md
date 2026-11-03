---
id: "media-display"
title: "View photos and files"
kind: "feature"
status: "implemented"
summary: "Uploaded photos may be cached locally; message existence does not guarantee local image bytes."
parent: "media"
sources:
  [
    "Sources/NessaFeatures/Presentation/Components/PhotoAttachment.swift",
    "Sources/NessaFeatures/Presentation/Components/PhotoCardStack.swift",
    "Sources/NessaFeatures/Presentation/Components/LoopingPhotoPager.swift",
    "Sources/NessaFeatures/Presentation/Components/AgentFileArtifact.swift",
    "Sources/NessaFeatures/Infrastructure/AttachmentImageCache.swift",
    "Sources/NessaFeatures/Application/FileTextPreview.swift",
  ]
sourceRevision: "8a027f07ecc1b27fb63502852648cb467e308720"
diagramLinks: {}
---

# View a photo or file in a conversation

Photos display as bubbles or a swipeable stack. View all opens a gallery and an
iPhone viewer supports zooming. Thumbnails are prepared off the main actor; the
inline stack commits the next image after its exit animation and can loop in
either direction. A full-screen page gesture is separate from navigating back.

Live uploads can be retained in an identity-scoped bounded device cache across
relaunches. The current gateway has no photo-retrieval endpoint for this client.
A photo from another device, or one evicted from the OS cache, can therefore show
an unavailable placeholder while the message itself is still valid. Retrying the
conversation read is not a promise to download those bytes.

File tiles show original name, type, size and digest references. They do not
invent a local filesystem path or imply that the phone can execute an artifact.
A bounded text preview is a presentation helper, not a file synchronization API.

Tests exercised image preparation, policy, swipe state, metadata and text-preview
contracts on macOS. Simulator/physical zoom, gestures, accessibility and cache
pressure were not run. The immutable artifact values and these UI contracts are
not represented by an invented persistent lifecycle model.
