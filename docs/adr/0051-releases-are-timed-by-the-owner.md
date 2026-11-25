# 0051 - Releases are timed by the owner, not by milestone closes

- Status: accepted
- Date: 2026-11-25 (owner decision)
- Partly supersedes: [ADR-0009](0009-release-versioning.md), its "one minor version per milestone" rule only. SemVer, release commits, build numbers, prereleases for user-only checks and the local release tasks stay in force, as does the rest of ADR-0009. Release notes stay as [ADR-0029](0029-release-notes-come-from-each-proposal.md) defines them.
- Source: owner decision on 2026-11-25, with the `v0.10.0` release

## Context and problem

ADR-0009 tied the minor version to milestones: a milestone close bumped the minor version, and fixes between milestones bumped the patch version. Milestones have grown to several features each, so finished features and fixes wait for the whole milestone before players get them. M10 had audio alerts, screenshot cleanup and several map and screenshot-reading fixes on `main` while its last changes were still open.

## Decision

- **The owner decides when to release,** based on the fixes and features on `main`. A release can come in the middle of a milestone. A milestone close may still bring a release, but does not have to.
- **The version follows what the release contains.** A release with new features raises the minor version; a release with only fixes raises the patch version. Prereleases (`-beta.N`) for user-only checks are unchanged.
- **Release notes are unchanged.** `release:prepare` still lists every change archived since the last final release, so a release lists what is new since the previous one, whether or not a milestone closed in between.

## Consequences

- Agents no longer offer a release only at a milestone close; they leave the timing to the owner.
- A version number no longer maps to a milestone. The roadmap's Done entries and the changelog say what each release contains.
- Releases may be more frequent. The release workflow's accepted gap in ADR-0026 (two final versions published within one run could both be marked Latest) is still unlikely, because releases are started by hand one at a time.
- The "whole milestone" wording in ADR-0009 and ADR-0029 now reads as "everything since the last final release"; the tooling already works that way.
- **Reversal cost:** low. It changes documentation and agent rules only; no tool or stored format depends on it.
