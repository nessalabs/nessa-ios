# Current gateway contract verification

Gateway source: `afbeb468ba54528835fbf152046472042ac612ff`. Phone source:
base `c3e86d393b06470d3fa6c0142098c4396a134998` plus this PR's owner-generated
grammar, source pin, ready-boundary tests and canonical channel-page fixtures.
The prebuilt native package is unchanged.

The original frozen grammar rejected the live gateway in both engines
(`invalid response`, raised run5/9). Regenerating through the owning generator
from the exact reviewed gateway, with no server change, passed9/9 in EACH
Chromium and WebKit. The raised plan uses seed19,channels3,inputFiles3,
parallel3,turns2,followers2,rounds6. The actual Swift phone model sends PDF,ZIP
and text through both prepared journal and persistent outbox; the gateway
verifies placed bytes, stable execution identity, retained references and
visible names while background turns/followers run. This does not drive a
physical phone's picker or establish a full default-plan pass.

Full Swift tests:425 passed. The first refreshed run found an old channel-page
fixture omitted the three now-required canonical placement/coordinator fields;
the fixture was corrected without relaxing the decoder or its assertions.
Architecture/design-system verifiers, workflow actionlint and generator drift
check passed.

Counterfactual: regenerating the OLD pinned grammar through its owner makes
the updated valid-at-limit ready test fail. Restoring the current generated
grammar passes all3 ready tests, including malformed,unknown-field and
over-limit refusals. The exact source/exit receipts are in contract-probes.json.
No wildcard acceptance, server catalogue filtering, raw gateway logs, temporary
phone credentials or configuration files are included.
