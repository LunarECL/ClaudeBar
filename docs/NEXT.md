# Menu bar account label visibility

## Status, October 1, 2026

Submitted [PR #365](https://github.com/tddworks/ClaudeBar/pull/365), open and ready for review. Working branch: `feat/hide-menu-bar-account-labels`, based on upstream `main` at `5af5c1c`.
Earlier contribution #220 was merged. Open PR #358 shortens account labels but does not add a visibility toggle. Live PR and issue searches found no duplicate hide-label option.

Implemented a global Show Account Labels in Menu Bar switch, default on, persisted through the existing settings repository. The renderer omits the account text when disabled, preserving icons, quota layout, tooltip identity, and accessibility descriptions. The observable setting is carried in LabelContent so changing it repaints immediately. Settings search finds the option with account, email, or label.

## Unfinished

Implementation, local verification, documentation, and the changelog are complete. GitHub CI is running; maintainer review, merging, and an upstream release are pending at PR #365. The installed application has not been replaced.

## Next action

```bash
gh pr checks 365 --repo tddworks/ClaudeBar
```

If a check fails, inspect its logs and resolve any failure caused by this change. If the checks pass, the next step is maintainer review. There are no local servers or watchers to stop.

## Re-verify

| Claim | Command | Result, October 1, 2026 |
|---|---|---|
| Earlier contribution merged | `gh pr view 220 --repo tddworks/ClaudeBar --json state` | MERGED |
| No duplicate toggle | `gh pr list --repo tddworks/ClaudeBar --state open --limit 100` and related issue/PR searches | No hide-label toggle found; #358 overlaps label rendering |
| Full suite | `xcodebuild test -workspace ClaudeBar.xcworkspace -scheme ClaudeBar -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/claudebar-derived -resultBundlePath /private/tmp/claudebar-full.xcresult -disableAutomaticPackageResolution -skipMacroValidation` | Passed: 2,567 tests, zero failures; compatible aged dependencies used locally |
| Native rendering and persistence | Same command with a fresh result path and `-only-testing:AppTests/CodexAccountIconTests -only-testing:AppTests/AppSettingsMenuBarTests -only-testing:AppTests/SettingsSectionSearchTests -only-testing:InfrastructureTests/JSONSettingsRepositoryAppTests` | Passed after strengthening the reference image comparisons; normal and stacked layouts, primary and additional accounts |
| Docs | `python3 scripts/gen-docs.py` then `python3 scripts/check-docs.py --strict` | Passed; re-run before each push |
| Whitespace | `git diff --check` | Passed; re-run before each commit |
| Upstream CI | `gh pr checks 365 --repo tddworks/ClaudeBar` | UNVERIFIED: build, tests, docs, and CodeRabbit pending at submission |

## Traps

- Tuist test results may be cached. Use xcodebuild for a fresh run.
- Use a fresh result bundle path on every run; xcodebuild will not overwrite one.
- The manifest uses version ranges and SweetCookieKit has a release from today. Local testing temporarily exact-pinned an audited dependency graph older than 14 days, including SweetCookieKit 0.3.0 and AWS SDK 1.6.99. Tuist/Package.swift was restored before committing. Generated lockfiles, build output, audit evidence, and images are not committed. Upstream CI with its own resolution is a separate check.
- AppTests launch the application as a test host. The generated local scheme sets CFFIXED_USER_HOME to /private/tmp/claudebar-test-profile to keep normal settings separate. This scheme edit is not committed.
- PR #358 edits the same renderer. The toggle should gate account label rendering independently of how those labels are shortened.

## Waiting on the requester

Nothing. The user authorized checking GitHub, implementing the option, and submitting a new PR if there is no duplicate.
