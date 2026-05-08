# Coding Standard

## Workflow

Every non-trivial change follows this loop:

1. Plan: state the concrete slice, expected files, tests, and verification commands.
2. Plan review: check whether the slice is small, testable, aligned with DDD, and uses the design system.
3. Implement: make scoped edits only.
4. Implementation review: inspect the diff, run tests/verifiers, and compare results to the plan.
5. Iterate: fix review failures until the slice passes.
6. Close: mark the plan item done and list any remaining risks or callouts.

## Architecture

- Use DDD-style boundaries:
  - `SharedKernel`: stable cross-domain value types and primitives.
  - `Features/*/Domain`: entities, value objects, domain services, and ports.
  - `Features/*/Application`: use cases and orchestration.
  - `Features/*/Infrastructure`: local host, persistence, logging, networking, and external adapters.
  - `Features/*/Presentation`: SwiftUI screens and view models.
  - `DesignSystem`: tokens, components, icons, layout primitives, and previews.
  - `Observability`: logging, metrics, traces, and diagnostics abstractions.
- Domain targets must not import SwiftUI, UIKit, Foundation networking details, or infrastructure modules.
- Presentation targets may depend on application, domain, observability, and design system modules.
- Infrastructure targets implement protocols declared by domain or application layers.

## Swift

- Prefer value types for immutable data and small domain concepts.
- Use protocols for ports at domain/application boundaries; avoid protocol abstractions for simple internal helpers.
- Prefer async/await for asynchronous work.
- Keep view models thin: screen state, user intents, and use-case calls only.
- Use `Logger` through the `Observability` module rather than direct scattered logging.
- Avoid global mutable state. Inject dependencies through initializers or environment containers.
- Keep comments sparse and useful. Explain non-obvious decisions, not syntax.

## SwiftUI

- Product screens must use `ClawdiaDesignSystem` tokens and components.
- Do not hard-code product colors, fonts, spacing, radii, shadows, or button styles in feature views.
- Use `NavigationStack` by default for screen-to-screen navigation unless a user request or platform constraint explicitly calls for another navigation model.
- Prefer small, named subviews when a view body becomes difficult to scan.
- Extract shared components for repeated product patterns instead of copy-pasting view structure.
- Keep accessibility labels on icon-only controls and custom interactive components.
- Use previews or dev-mode screens for reusable components and flows.

## Testing

- Write tests before or alongside implementation for domain behavior, application use cases, routing state, and verifier rules.
- Use Swift Testing for package-level unit tests when available.
- If the local command-line toolchain does not expose XCTest or Swift Testing, use the `ClawdiaVerificationTests` executable target so verification remains runnable.
- Use XCTest for UI automation once an Xcode app target is available.
- Verifier scripts must fail fast and explain the boundary or design-system rule that failed.

## Tooling

- Default automation language is Swift or POSIX shell.
- Do not add script runtimes or package managers unless the project genuinely needs them.
- Verification entry point is `./scripts/verify.sh`.
- Keep generated artifacts and build products out of source control.

## Review Pass Criteria

A slice passes only when:

- Planned files were created or changed.
- Tests for the slice pass.
- Architecture and design-system verifiers pass.
- The implementation was inspected for DDD boundary leaks, hard-coded styling, and observability gaps.
- Repeated UI patterns were checked for reusable component extraction.
- Risks and incomplete follow-ups are recorded.
