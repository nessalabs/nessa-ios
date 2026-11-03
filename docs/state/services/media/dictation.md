---
id: "media-dictation"
title: "Finish or cancel dictation"
kind: "statechart"
status: "implemented"
summary: "Only the current speech session can update the draft-facing transcript."
parent: "media"
sources:
  [
    "Sources/NessaFeatures/Presentation/ViewModels/DictationViewModel.swift",
    "Sources/NessaFeatures/Infrastructure/AppleSpeechTranscriber.swift",
    "Sources/NessaFeatures/Infrastructure/SpeechPermissionCallback.swift",
    "Sources/NessaFeatures/Application/SpeechTranscribing.swift",
    "Tests/NessaFeaturesTests/DictationTests.swift",
  ]
sourceRevision: "8a027f07ecc1b27fb63502852648cb467e308720"
diagramLinks: {}
model:
  {
    "spec": "tla/DictationGeneration.tla",
    "config": "tla/DictationGeneration.cfg",
  }
modelCheck:
  sourceRevision: "8a027f07ecc1b27fb63502852648cb467e308720"
  checker: tlc-1.7.4
  date: 2026-11-03T08:48:10.363Z
  config: tla/DictationGeneration.cfg
  modelDigest: dbcb0d41b045dc9eae842c5b8adffafa02def4f99c6f681f5938f6c92a875c67
  states: 8
  held:
    - CurrentTranscriptOnly
    - CurrentCleanupOnly
  broke: []
  unchecked: []
diagramDetails:
  [
    {
      "diagram": 0,
      "node": "Idle",
      "section": "Stopped recognition leaves recognized text",
    },
  ]
---

# Dictate text and cancel stale results

Tap the waveform to turn speech into text. Live mode asks for microphone and
speech-recognition permission; development supplies a mock transcript. When
listening, tap again to finish recognition, review the text, then tap Send.
Dictation does not itself submit a chat or send an audio recording.

The same control behaves differently by stage. While permission/start is pending,
tapping it cancels that request. While listening, tapping it asks recognition to
finish and waits for final text; the busy control is disabled while finishing.
There is no separate Cancel button for an active listening stream. Leaving the
composer or moving the app to background cancels recognition. Inactive scene
transitions also cancel except while the permission request is pending.

```mermaid
stateDiagram-v2
  [*] --> Idle
  Idle --> Requesting: Start new speech session
  Requesting --> Listening: Permissions and transcriber start succeed
  Requesting --> Idle: Cancel or start fails
  Listening --> Finishing: Ask for final text
  Listening --> Idle: Stream finishes or fails
  Finishing --> Idle: Final stream result or failure
  Listening --> Idle: Cancel and invalidate session
```

Each start gets a fresh token, meaning the identity of that speech session.
Callbacks and final cleanup compare their captured token with the current one.
Cancelling rotates it before cancelling the task and transcriber. A late result
from an older session cannot replace the new transcript or reset the new state.
Cancelling does not erase text already recognized: the composer copies each
nonempty transcript update into its draft and leaves that draft when dictation
is cancelled. Leaving the composer or backgrounding the app cancels recognition,
not the text already copied.
A stream ending without a final result is an incomplete-recognition error,
not an invented successful transcript.

`DictationGeneration` explores one old stream and one replacement session. It
checks that accepted transcript updates and cleanup belong to the current token.
Controls remove each comparison. Permissions, Apple callback threading and
physical microphone recognition remain separate implementation/platform concerns.
Dictation and speech-permission callback tests passed locally; no physical speech
recording was performed.

## Stopped recognition leaves recognized text

Cancelling prevents later callbacks from changing the current transcript. It
does not erase text already copied to the message field and does not send it.
Review the draft and tap Send separately. A new speech session ignores the old
session's late callbacks and cleanup.
