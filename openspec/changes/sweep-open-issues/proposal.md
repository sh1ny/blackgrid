# Proposal

## Why

Eighteen GitHub issues are open (#10, #16, #17, #19-#21, #23-#25, #28-#30, #33, #34, #38, #48, #52, #55). Most are review follow-ups deferred at merge between 2026-10-07 and 2026-10-29, and the code they cite has moved since. Nobody has decided which of them still matter before a release, so M6 (replacement qualification) would start with an unjudged backlog.

This change serves milestone **M4.6 - open-issue sweep** (change 1). It advances every exit criterion of M4.6:
- every open issue not already assigned to a milestone gets a verdict agreed with the user (fix now, defer to after 1.0, or close), recorded on the issue with its reason;
- an issue that no longer applies is closed with the evidence;
- an issue that still applies but is too minor or unlikely before 1.0 is deferred, not fixed;
- each "fix now" issue gets a change in M4.6 that will close it (the fixes themselves are later changes).

## What Changes

- **Re-check each open issue against current `main`.** For each one: does the cited code still exist and behave as described, is the bad path reachable in the shipped app, and how likely and how bad is it. Findings cite current `file:line` evidence, not the review that filed the issue.
- **Propose a verdict per issue** with a one-line reason: close, defer to after 1.0, or fix now. The user decides each verdict; the agent proposes only.
- **Record each agreed verdict on its issue** as a comment with the reason.
  - Close: the issue is closed with the evidence that it no longer applies.
  - Defer: the issue stays open with a `post-1.0` label (created if missing), so the M6 and later sweeps can tell it apart from unjudged issues.
  - Fix now: the comment names the M4.6 change that will close it.
- **Add the agreed fixes to the M4.6 roadmap** (`openspec/roadmap.md`) as small changes grouped by area. Each one names the issues its PR closes and replaces the placeholder entry "2. The fix changes the sweep adds."
- No application code, test, spec or ADR changes. The fix changes are proposed, reviewed and built separately.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. This is a planning and issue-tracker change with no spec-level behaviour, so `.openspec.yaml` sets `skip_specs: true`.

## Impact

- `openspec/roadmap.md`: the M4.6 Changes list.
- GitHub issues on `sh1ny/blackgrid`: comments, closes and a `post-1.0` label, posted as `KintsugiBot` only after the user agrees each verdict.
- Issues that a milestone already names stay with that milestone and are not re-judged. None of the 18 open issues is assigned that way today: #48 is only mentioned in M4's Done line as a learning.
