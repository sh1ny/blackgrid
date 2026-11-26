# Review

## Metadata

- **Round:** 4
- **Prior round:** Round 3 approved with changes; both Ember planning corrections were applied and accepted by the reviewer. This round reviews only the owner-approved AOT amendment.
- **Reviewer:** fresh-context subagent (OMP)
- **Reviewed:** S3, D5, A4 and task 2.1 in `proposal.md`, `design.md` and `tasks.md`; prior `review.md`; active FULL review instructions and template; cited tracked source and ADRs; `capture_policy.dart`, the immutable `RawCapture.frameId`, the two offline ownership tests, the existing inspection-capture and CI requirements, Dart SDK issue #64917, and the reported Windows AOT trace. The re-check was limited to the two required design edits and the revised task 2.1 evidence wording. No builds, lint or tests ran for this review.

## Findings

### Critical (blocking)

None. The red trace names `CapturePolicy.capture` immediately before `linearscan.cc:3013` and the `aot_elf_release` failure. The tracked implementation matches the deferred-final closure pattern in #64917. `RawCapture.frameId` is a final `int` (`lib/data/capture/capture_native.dart:164–175`), so binding it after the success case preserves the release target. The raw error still returns before acquiring frame ownership; the rejection checks still release the acquired ID; success still returns the frame (`lib/data/capture/capture_policy.dart:51–109`). A4 and task 2.1 correctly leave the AOT outcome unproven until the same target compiles and require both unchanged offline ownership tests and the unchanged hosted Release gate.

### Moderate

1. **The compiler diagnosis lacked a tracked application-source citation, and D5 did not explicitly say `final`.** The original AOT paragraph linked the CI run and upstream compiler issue, neither of which shows the application code that task 2.1 is allowed to change. The original D5 said to initialize an ID but did not specify a declaration-initialized `final` outside the switch. Fixed; see Rebuttals.
2. **The capture invariant had no authoritative destination in Carried constraints.** D5 and A4 preserved rejection release and successful handoff, but the carried-constraints list did not connect this ownership-sensitive edit to the existing requirement it must preserve. Fixed; see Rebuttals.

### Suggestions

None.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

Both required changes were applied and accepted on re-check. They make the exact source boundary and existing ownership contract auditable without changing the owner decision, SDK, dependencies, runtime behavior, tests or gates. Successful compilation, test results and hosted bundle proof remain apply evidence, not review results.

## Required Changes

1. In the AOT baseline paragraph in `design.md`, cite `lib/data/capture/capture_policy.dart:51–65` for the switch-assigned `capture` and its use in the rejection closure. In D5, specify `final frameId = capture.frameId;` after the successful switch, use `frameId` only in `reject`, and leave frame lookup and success construction unchanged. Keep S3's #64917 removal comment condition: the Flutter pin bundles Dart 3.14.1 or later.
2. Add one carried invariant for unchanged single-owner frame release and handoff, with the sole destination `spec: specs/inspection-capture/spec.md → Requirement: Frame ownership is single and bounded`. Do not add or modify any spec or ADR.

CHANGES_APPLIED: yes

## Rebuttals

- **Round 2 critical and moderate findings — fixed, previously accepted in round 3.** The owner-approved Ember migration retains the generator as source of truth and preserves the byte-identical copy check; the Material diagnostic claim is limited to the observed apply failure.
- **Round 3 findings 1 and 2 — fixed, previously accepted in round 3.** D4 and task 1.3 retain the pinned format-then-copy procedure and import-only comparison, including unchanged CSS and token inputs. Proposal Impact retains the downstream `material_ui` prerequisite. The AOT amendment does not reopen either finding.
- **Round 4 finding 1 — fixed, accepted by reviewer.** `design.md:30,68` cites the tracked trigger, declares the exact post-switch `final` binding, uses it only in `reject`, preserves frame lookup and success construction, and supplies the #64917 removal condition. `tasks.md:16,20` separates same-target AOT and offline ownership evidence from the unchanged hosted Release, bundle, qualification and packaging proof; no gate is removed.
- **Round 4 finding 2 — fixed, accepted by reviewer.** C11 (`design.md:107`) adds one carried invariant with the sole destination `Frame ownership is single and bounded` in the existing `inspection-capture` spec (`openspec/specs/inspection-capture/spec.md:175–188`). No delta requirement is needed.
