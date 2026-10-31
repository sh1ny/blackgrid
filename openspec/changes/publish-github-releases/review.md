# Review

## Metadata

- **Round:** 1
- **Prior round:** First run of round 1 (same reviewer route): APPROVE_WITH_CHANGES, no Critical, one Moderate (M1: a `contents: read` preflight cannot see drafts and tag-name addressing is ambiguous among drafts), Required Changes 1-3, Suggestions S1-S4; CHANGES_APPLIED: no. This is the re-check run of those Required Changes only.
- **Reviewer:** fresh-context subagent (Claude Code, specwright-reviewer)
- **Reviewed:** Re-check scope: openspec/changes/publish-github-releases/design.md (D2, D3, D4, D5, D7, Diagrams, State & Ownership, Failure & Visibility, Resource Bounds, Flow & State Gaps, Mechanism Ledger, Risks); specs/release-publishing/spec.md; specs/continuous-integration/spec.md (for the least-privilege wording that Required Change 2(a) touches); proposal.md; the Rebuttals in review.md. The first run's full review covered proposal.md, design.md, all three spec deltas, .github/workflows/ci.yml, tool/release/src/{tag_step.dart, push_identity.dart, release_steps.dart, build_step.dart, package_step.dart, semver.dart}, tool/changelog.dart, cliff.toml, CHANGELOG.md, mise.toml, .gitignore, openspec/specwright.yaml, docs/adr/0009 and 0025 (relevant sections).

<!-- This verdict covers only the contents reviewed. Editing proposal, specs or design afterward (other than applying Required Changes, or an edit confined to the proposal's `## Release Notes` section) voids it. -->

## Findings

### Critical (blocking)

None.

### Moderate

**M1. The draft guard cannot work as designed: a `contents: read` token cannot see drafts, and a tag name does not identify one draft.** (resolved)
Original finding: preflight used `gh release view <tag>` with a read token, which sees published releases only. The design relied on `gh release create` failing with "already exists" on a leftover draft, but several drafts can share a `tag_name`. Later `gh release view`/`edit` calls addressed the release by an ambiguous tag name.
Re-check: resolved. D2 defines one release-existence check: a paginated `GET /releases` filtered on `tag_name`, run with the write token so drafts are listed. It records why a read token, `GET /releases/tags/<tag>` and a create failure are each insufficient. Preflight (with `contents: write`, no checkout) and publish (D5 step 1, immediately before the POST) both run it. D5 creates the draft through `POST /releases`, keeps `id` and `upload_url`, and addresses the uploads, the asset check (`GET /releases/<id>`, three names, state `uploaded`) and the final `PATCH /releases/<id>` (`draft: false`, `make_latest`) by id. It explicitly rejects tag-name addressing. The "already exists" reliance is gone from Flow & State Gaps and Risks. The remaining unguarded window, between publish's listing and its POST, is named and accepted in Flow & State Gaps with a concrete justification.

### Suggestions

**S1. Refuse a manual run dispatched from a ref other than `main`.** (adopted) D2 refuses a manual run unless `github.ref` is `refs/heads/main`. Spec scenario "Manual run from another branch", the requirement text ("a manual run from `main`"), proposal What Changes, D7 and the Mechanism Ledger agree. No contradiction found.

**S2. Do not let the "annotated" check depend on how actions/checkout writes the tag ref.** (adopted) The annotated check moved to preflight (`git/ref/tags/<tag>`, `object.type == tag`), and D3 no longer performs it. The spec requirement "Only a valid release tag is built" still says "Before building", and preflight runs before the build, so the "Lightweight tag" scenario still holds. The added D5 step 2 compares the tag against preflight's `tag_object` before the POST. It is consistent with Flow & State Gaps "Tag deleted or replaced mid-run" and with the diagram's `tag_object` edge. No contradiction found.

**S3. Spec wording: the whole workflow does not run on Windows.** (adopted) The requirement now says the tagged commit is built and gated on a hosted Windows runner, which matches D2's ubuntu preflight and publish.

**S4. The mechanism ledger overstates `sha256sum -c`.** (adopted) D4 adds a `sums_sha256` job output from `gates.yml`, exposed through the reusable workflow's `outputs:`. The ledger row for `sha256sum -c` no longer claims to catch substitution, and a separate row covers the digest. Spec requirement "A release holds exactly the packaged assets" and the scenario "Whole set replaced between jobs" match it, and State & Ownership names the output as the artifact's authoritative copy. No contradiction found.

No new findings. The S1-S4 edits introduced no contradiction or defect with a concrete consequence.

## Verdict

VERDICT: APPROVE_WITH_CHANGES

## Required Changes

1. design.md D5 and Flow & State Gaps: in `publish`, immediately before `gh release create`, list the repository's releases with the job's `contents: write` token (`gh api --paginate repos/$GITHUB_REPOSITORY/releases`, filtered on `tag_name == <tag>`, drafts included), and refuse naming each match if any exists. Capture the created release's id (create through `gh api -X POST .../releases` with `draft: true`, or resolve the id once right after create). Do the asset check, the asset uploads if they are done separately, and the final `PATCH ... draft=false, make_latest=...` against that id, never against the tag name. Replace the "gh release create then fails with 'already exists'" statements (Flow & State Gaps "Rerun of failed jobs only", Risks third bullet) with this check.
   - Re-check: applied. D2 (check definition), D5 steps 1, 3-6 and the "by id" paragraph, Flow & State Gaps "Rerun of failed jobs only" and "A draft created by hand while the gates run", Risks third bullet, the sequence diagram and the Mechanism Ledger row.
2. design.md D2 and spec release-publishing: choose one of the following and make the design and the spec agree.
   - (a) Give `preflight` `contents: write`. It has no checkout and runs only `gh`, which is the same justification D2 gives for `publish`. Have it use the same releases listing so it sees drafts. Update the "Only the publishing step can write" requirement and its "Permissions per job" scenario to say that only `preflight` and `publish`, which run no repository code, widen to `contents: write`, and update the continuous-integration delta text that says "only the publish job of the release workflow holds `contents: write`" (proposal Capabilities).
   - (b) Keep `preflight` read-only, checking published releases only. Amend the "Release already exists" scenario: a published release is refused before building, and a draft is refused by the publishing step before any release call, after the gates have run.
   - Re-check: applied with option (a). D2 gives preflight `contents: write` with no checkout and the same listing. It rejects the read-only alternative and adds an offline test: a write job has no checkout, no `mise` and no local `uses:`. Spec requirement "Only steps that run no repository code can write" names the pre-build check and the publishing step. Its "Permissions per job" scenario names preflight and publish, and the new "A write job gains a checkout" scenario is assertable. "Release already exists", "Draft already exists" and "Draft appears while the gates run" match D2/D5. Proposal What Changes and the continuous-integration capability line say preflight and publish. The continuous-integration delta constrains only `ci.yml` and `gates.yml`, so it does not conflict. The diagram, State & Ownership and Risks (new "Preflight now holds a write token" bullet) agree.
3. design.md State diagram note, Failure & Visibility rows "publish: create or upload" and "publish: `edit --draft=false`", and the README recovery text the design prescribes: name the check that actually refuses a run while a draft exists (the publish-time check from change 1, plus preflight if 2(a) is chosen).
   - Re-check: applied. The state diagram note, the Failure & Visibility rows (preflight, "publish: verification, existence or tag check", "publish: create or upload", "publish: final `PATCH draft=false`") and the D7 README recovery text all name the write-token release listing in preflight and publish.

CHANGES_APPLIED: yes

## Rebuttals

- **M1 / Required Change 1:** fixed. D2 defines a release-existence check (paginated `GET /releases` filtered on `tag_name`, write token, drafts included). D5 runs it immediately before the POST, creates the draft through `POST /releases`, keeps its `id`, and addresses the uploads, the asset check (`GET /releases/<id>`) and the final `PATCH /releases/<id>` (`draft: false`, `make_latest`) by that id. Flow & State Gaps "Rerun of failed jobs only" and the Risks bullet now name this check; the "already exists" reliance is gone. *(Reviewer: fix verified; no rebuttal to accept.)*
- **Required Change 2:** fixed with option (a). `preflight` holds `contents: write`, checks out nothing and runs the same listing (D2). Spec release-publishing: the requirement is now "Only steps that run no repository code can write", its "Permissions per job" scenario names preflight and publish, and a "A write job gains a checkout" scenario was added. "Release already exists" covers a published release, and "Draft already exists" and "Draft appears while the gates run" cover drafts. Proposal "What Changes" and the continuous-integration capability line were updated to match. *(Reviewer: fix verified.)*
- **Required Change 3:** fixed. The state diagram note, the Failure & Visibility rows (preflight, "publish: verification, existence or tag check", "publish: create or upload", "publish: final `PATCH draft=false`") and the README text prescribed in D7 now name the release listing in preflight and publish. *(Reviewer: fix verified.)*
- **S1:** adopted. A manual run refuses unless `github.ref` is `refs/heads/main` (D2), with a new spec scenario "Manual run from another branch".
- **S2:** adopted. The annotated check moved to preflight through `git/ref/tags/<tag>` `object.type == tag` (D2), and verify-tag no longer checks it (D3). Publish also re-reads the tag before the POST against preflight's `tag_object` (D5 step 2), which guards the POST against creating a tag from the default branch.
- **S3:** adopted. Spec wording: the tagged commit is built and gated on a hosted Windows runner.
- **S4:** adopted. A `sums_sha256` job output from `gates` pins `SHA256SUMS.txt` (D4), with a spec scenario "Whole set replaced between jobs" and a ledger row.
