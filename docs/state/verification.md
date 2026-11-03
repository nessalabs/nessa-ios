---
id: "verification"
title: "Checks and evidence"
kind: "guide"
status: "reference"
summary: "Separate source review, executed Swift tests, bounded models and device evidence."
parent: "nessa-ios"
sources:
  [
    "scripts/verify.sh",
    "scripts/verify_architecture.sh",
    "scripts/verify_design_system.sh",
    "verification/sync/README.md",
    "Package.swift",
  ]
sourceRevision: "8a027f07ecc1b27fb63502852648cb467e308720"
diagramLinks: {}
---

# What was checked and what remains untested

This atlas was traced at source
`8a027f07ecc1b27fb63502852648cb467e308720`. The checkpoint means source was
reviewed; it is not proof of a deployed gateway or an iPhone test run. Current
normal composition was checked separately from implemented but unwired APIs.

## Executed implementation baseline

On November 3, 2026, `./scripts/verify.sh` passed the architecture verifier,
design-system verifier, Swift build and all **425 Swift Testing tests in two
suites** on arm64 macOS. The XCTest wrapper reported zero tests before Swift
Testing ran; the 425 count is the actual Swift Testing result. This included
application/view-model tests, private-store fault cases and native macOS adapter
checks with fixtures. No application source was changed for this atlas.

## Documentation and model checks

From the repository root, with Node and a built Nessa Docs checkout whose pinned
checker cache is installed:

```sh
NESSA_DOCS_ROOT=/absolute/path/to/nessa-docs node scripts/state-docs/verify.mjs --write
```

The runner checks the catalog, runs each original model and then applies its
persisted negative controls in memory. Only original baseline results are written
to page metadata. It does not install a checker automatically. A negative control
must break the named semantic rule with no unchecked properties; a syntax error
or timeout is not a successful control.

Current canonical results: **29 catalog pages**, **8 models**, **17 configured
invariants** and **17 negative controls**. All baselines held their rules and all
controls broke the expected rule, with no unchecked result. The independent
models explored 90 states in total; this is not a product capacity or throughput
measurement. The final run includes a corrected recovery invariant identified
by independent adversarial review.

[Control definitions](../../verification/state-models/controls.json),
[saved results](../../verification/state-models/results.json) and the
[review record](../../verification/state-models/review.md) retain the commands,
bounds, model digests, findings and resolutions. Chrome 156 opened all 29 pages
and rendered 15 diagrams without page or diagram errors; see
[browser evidence](../../verification/state-models/browser-results.json).
This checks the docs renderer, not the phone UI. A separate normal-view browser
exercise opened Unknown delivery, Forget and Dictation Idle explanations and
confirmed their critical text was visible; see
[reader browser evidence](../../verification/state-models/reader-browser.json).

The independent [reader retest](../../verification/state-models/reader-round2.md)
passed the revised connection-switch and cancellation tasks. The
[independent source/model review](../../verification/state-models/independent-technical-review.md)
closed the pairing wording and recovery-invariant findings. These are sampled
reviews, not a human usability study or an exhaustive code audit.

## Separate environments and limits

- iPhone simulator build, physical camera/microphone, Keychain entitlements,
  VoiceOver, gestures and iOS 26 visual behavior were not exercised here.
- Real gateway/provider, TLS/native remote identity, upload placement, push and
  mobile network transitions were not exercised. Mock transport is not a live
  authorization check.
- [Native fixture runner](../../verification/sync/README.md) and
  `./verification/sync/run-fixtures.sh` have their own prerequisites; they were not
  run as part of `verify.sh` in this pass.
- File stress uses `scripts/verify-phone-files-stress.mjs`, the compiled verifier
  and an exactly pinned gateway checkout with browsers/dependencies. That broader
  experiment and physical file-picker operation were not run.

The TLA models cover selected finite ordering/identity rules. They do not prove
all feature interleavings, liveness, unlimited queue sizes, filesystem durability
or automatic correspondence with Swift/Rust. The [inventory](inventory.md) names
source-reviewed areas without a model instead of counting them as formal passes.
