# Publishing a release

Development happens in [folzio-dev](https://github.com/yoshidax/folzio-dev).
The [distribution repository](https://github.com/yoshidax/folzio) contains the published source and releases.
Ordinary development changes do not update the distribution repository.

## Prepare a release pull request

Every development pull request checks the public source snapshot of its checked-out commit before building.
Home paths, README mismatches, and excluded-file leaks are detected without waiting for a release request.

1. In the development repository, copy `release.example.json` to `release.json`.
2. Choose an unused `version`, a `build_number`, and a Markdown file under `release-notes/`.
   The candidate checks public tags and releases before building; an already used version is rejected.
   Both numeric fields are strings. Version components and the build number allow `0` alone, but reject leading zeros.
   For example, `1.02.0` and build `007` are invalid. Unknown and duplicate keys are rejected.
3. Commit the notes and request in the same pull request. Notes must contain text and must be regular committed files.
4. Wait for **Release candidate**. Its summary links to an artifact named
   `release-candidate-<source SHA>-<run ID>-<attempt>`.
5. Download it from the Actions run's **Artifacts** section. Extract the outer archive to get the application ZIP,
   `SHA256SUMS`, `candidate.json`, and the performance measurement log.

## Check the application locally

Use an Apple silicon Mac with macOS 15 or later. No local build is needed.
Check that `candidate.json` identifies the intended pull request, source, version, build, and successful required checks.
Performance measurements are recorded but do not block publication when a shared machine exceeds the timing thresholds.

```bash
shasum -a 256 -c SHA256SUMS
ditto -x -k Folzio-v1.2.3-macos-arm64.zip extracted
codesign --verify --deep --strict extracted/Folzio.app
open extracted/Folzio.app
```

Check all three panes, Japanese and English, and the version in About. Follow the README instructions for opening
an unsigned-by-Developer-ID, unnotarized application if Gatekeeper blocks it.
If the pull request changes, download and check its new candidate before merging.

## Merge and publish

Merge the release pull request after checking the candidate. **Publish release source** fixes the actual merge commit,
called **M**, and compares its published file tree with the checked candidate.
If they match, the validated source is synchronized as one new commit in the distribution repository.
That push starts **Build release draft**, which tests and builds the published commit, verifies the ZIP and checksum,
and creates a tag and draft release. Review the assets, notes and provenance, then publish the draft.

The final ZIP is rebuilt from the published commit using the same source tree and toolchain settings.
Its bytes can differ from the local-check ZIP because packaging and signing include build-specific metadata.
Releases target arm64, use ad hoc signing, and are not notarized. Intel and automatic application updates are not supported.

## A changed merge result or a failed release

The base branch can advance after preview generation. When M has different published files, the sync run generates
a new candidate for M and waits for another local check. The **Await local verification** job deliberately ends
with a failure status and **Not published**, so a successful candidate build cannot be mistaken for completed publication.
This also applies when the initial public base must be confirmed. The successful candidate job remains usable for resuming.

1. Download the new candidate, inspect `candidate.json`, and check it locally.
2. Open **Publish release source** → **Run workflow**, select the default branch, and enter
   `source_sha=M` and `candidate_run_id=<the checked candidate's run ID>`.
3. Keep using M even if the default branch has advanced. The workflow rejects a different ordinary commit that was
   not the merge result of a release-request pull request.

If a candidate expires after 30 days, use **Release candidate** → **Run workflow** with `source_sha=M` to rebuild it.
Then check it and resume with the same M and the new run ID. The default branch selects the workflow code;
it does not replace the explicitly selected source.

Use **Re-run failed jobs** for transient job failures. Downloads use the artifact ID saved by the successful plan job,
including when that job ran in an earlier attempt. A candidate is bound to the latest attempt that actually ran its build job;
a later failed build cannot fall back to an older candidate. A waiting run resumes through **Run workflow**, rather than
re-running the waiting job.

The selected commit supplies its own export rules and shared packaging script, even if the default branch has advanced.
Before changing public main, the writer checks tags and all visible releases again with the App's public-repository access.
This check includes drafts, which are absent from the release-by-tag endpoint and may be hidden from read-only preview jobs.

If the public source was already synchronized, repeat the original public build run to retry only the binary release.
An identical source synchronization creates no duplicate commit. An existing tag can be reused only for the same public commit.
The public plan uses read-only permissions, so an existing draft can be hidden from it.
The release job rechecks with its existing write permission immediately after checkout, before tests or builds.
An existing draft stops there; macOS startup and checkout still occur. The final check before creating a draft also remains.
Existing draft or published releases are never overwritten. Inspect a partial draft and repair or delete it manually before retrying.
Use a new version for a different published commit. Concurrent public updates stop with a conflict; never force the update.

## First publication

An initial public history without a source mapping requires explicit initialization. After checking the candidate,
obtain the current public main SHA:

```bash
gh api repos/yoshidax/folzio/git/ref/heads/main --jq .object.sha
```

Run **Publish release source** with M, the checked run ID, and that full SHA as `bootstrap_public_base`.
Missing or incorrect bases do not change the public repository. Once initialized, leave this field empty.
The first source-mapping commit is created even if its files match the existing public tree.

The maintainer must first configure a GitHub App installed only on the distribution repository, with Contents write
and Workflows write, and set `PUBLIC_SYNC_APP_CLIENT_ID` and `PUBLIC_SYNC_APP_PRIVATE_KEY` in the development repository.
The public branch protection must permit the App's normal updates. Publication does not alter branch protection automatically.
