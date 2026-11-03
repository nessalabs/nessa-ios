---
id: "history"
title: "Saved history and access"
kind: "service"
status: "implemented"
summary: "Cached display, current product authority and native retained access are separate facts."
parent: "nessa-ios"
sources:
  [
    "Sources/NessaFeatures/Application/PhoneRetainedHistory.swift",
    "Sources/NessaFeatures/Application/PhoneRetainedDisplay.swift",
    "Sources/NessaFeatures/Application/PhoneSnapshots.swift",
    "Sources/NessaFeatures/Presentation/ViewModels/MessagesViewModel.swift",
  ]
sourceRevision: "8a027f07ecc1b27fb63502852648cb467e308720"
diagramLinks: {}
---

# Read saved chats without inventing access

A disconnected screen can show saved conversation content without being allowed
to send. Conversely, the current live product outbox uses the product connection
rather than requiring a complete native retained-history refresh. Do not use one
blanket “synced” flag for both facts.

- [Read retained native history](retained.md): exact profile/receiver and page identity.
- [Prepare or retire a profile](profiles.md): durable preparation and recovery.
- [Save a derived display cache](snapshot.md): bounded local snapshots, not native authority.
- [Management APIs outside normal controls](management-apis.md): sharing, deletion and owner preparation.
- [Local storage and credentials](storage.md): persistence failures may leave visible bytes.

When a saved native profile is unavailable, corrupt or retired, the phone does
not silently substitute an older legacy cache as if access were valid. Only an
absent native registry permits the legacy fallback. The native library owns
physical retention and purge; the phone projects its observations into screens.
