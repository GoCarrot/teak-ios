# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Teak iOS SDK — an Objective-C framework providing push notifications, deep linking, rewards, and analytics for free-to-play mobile games. Published as a CocoaPod (`Teak`) and as pre-built xcframeworks.

## Build & Test Commands

**Spin up a worktree:**
```bash
# Create a sibling worktree with nvm, bundle, and yarn deps installed
script/worktree feat/my-feature                         # branch off HEAD
script/worktree feat/my-feature --from 4.3-stable       # fetch + fast-forward 4.3-stable first
script/worktree feat/my-feature --from develop ~/path   # custom path
```
Default path is `../teak-ios-<branch-with-slashes-as-dashes>`. Use `script/worktree` to create worktrees — do NOT use the `EnterWorktree` tool.

**Build the framework:**
```bash
./compile_xc_framework
```
Builds Teak.xcframework and TeakExtension.xcframework (simulator + device archives), zips them with SHA-512 checksums, and copies to `../teak-ios-framework`. Pass `-d` for a debug build.

**Run tests:**
```bash
bundle exec fastlane test
```
Runs from the repo root. Uses the `Automated/Automated.xcworkspace` with `scan`. Results output to `test_output/automated/results.xml` (JUnit format).

### Adding Tests

Tests live in `Automated/AutomatedTests/` and use XCTest with OCMockito (~> 5.0) and OCHamcrest for mocking/assertions.

**To add a new test file:**
```bash
bundle exec Automated/generate_test ClassName   # generates AutomatedTests/ClassNameTests.m and adds to Xcode project
```
The generator creates a boilerplate XCTest file with OCMockito/OCHamcrest imports and adds the file reference and build phase entry to the Xcode project. It's idempotent — safe to re-run on existing files.

**Header imports in tests:**
- SDK source headers via bare name: `#import "TeakPushState.h"` (HEADER_SEARCH_PATHS covers all SDK subdirectories)
- Framework public headers: `#import <Teak/Teak.h>`
- To access internal properties, re-declare them in a class extension in the test file rather than importing `Teak+Internal.h` (which pulls in headers not on the test target's search path)

**Creating Teak instances for testing:**
`[[Teak alloc] init]` bypasses `initWithApplicationId:andSecret:` and creates a bare instance with nil properties. This is safe for unit testing where you set only the properties under test. Production code must always use `[Teak sharedInstance]`.

**Test patterns:**
- `DebugConfigurationTests.m` — dependency injection with real objects (preferred when possible)
- `LogTests.m` — OCMockito mocking with `mock()`, `given()`, `stubProperty()`, `assertThat()`
- `NotificationSettingsTests.m` — bare Teak instance with mocked dependencies, internal property re-declaration

**Testing for race conditions:** see [`Automated/RACE_TESTING.md`](Automated/RACE_TESTING.md) — how to pick a detector for a given race class (ThreadSanitizer vs. a dynamic crash repro vs. a static assertion), why a green TSan run doesn't mean "safe" for nonatomic-strong pointers, and the revert check that makes any race test trustworthy. The `test_race` fastlane lane runs these guards under TSan (per-commit and as a release gate).

**Format code:**
```bash
./format-code
```
**DO NOT RUN** — clang-format 21 (current Homebrew version) reformats the entire codebase differently than the version originally used. The script and `.clang-format` config have been updated but the formatting rules need review before running on source. Follow the existing code style by hand for now.

**Generate documentation:**
```bash
npm run build   # runs: doxygen && doxygen2adoc
```

## Code Style

- Enforced via `clang-format` with the `.clang-format` config (LLVM-based, ObjC-specific)
- Key settings: 2-space indent, no column limit, attached braces, `ObjCSpaceAfterProperty: true`
- Pre-commit hook blocks commits that don't comply; apply the generated patch or run `./format-code`

## Architecture

### Source Layout

- `Teak/` — All SDK source (Objective-C). This is the main codebase.
  - `Teak.h` / `Teak.m` — Public API and singleton entry point (`+sharedInstance`, `+initForApplicationId:withClass:andApiKey:`)
  - `Configuration/` — Layered config system: app, device, remote, data collection, debug
  - `Events/` — Modular event types (UserIdEvent, PurchaseEvent, TrackEventEvent, etc.) for analytics
  - `Extensions/` — Notification service/content extension core logic
  - `Store/` — StoreKit payment observer for automatic purchase tracking
  - `Core/` — TeakCore, TeakUserProfile, TeakChannelStatus, TeakLaunchData
  - `3rdParty/` — Vendored: libtommath, UIImage+animatedGIF, provisioning profile detection
- `Sample/` — Reference app with notification service/content extensions
- `Automated/` — Test workspace (unit tests use OCMockito, UI tests)
- `TeakFramework/` — Pre-built xcframeworks (Teak.xcframework, TeakExtension.xcframework)
- `TeakExtensions/` — Source files for notification service and content extensions

### Key Patterns

- **Singleton SDK**: All access through `[Teak sharedInstance]`; one-time init via class method
- **NSNotification events**: SDK communicates with host app via named notifications (TeakNotificationAppLaunch, TeakOnReward, TeakForegroundNotification, TeakLaunchedFromLink, etc.)
- **Method swizzling**: `TeakHooks.m` intercepts UIApplication and UNUserNotificationCenter delegate methods
- **State machine**: `TeakState` manages SDK lifecycle transitions
- **Async operations**: `TeakOperation` and `TeakWaitForDeepLink` for deferred execution

### CocoaPods Structure

Two subspecs in `Teak.podspec`:
- `Core` (default) — Full SDK from `Teak/**/*.{h,m,c}`
- `Extensions` — Subset for notification extensions only

Platform minimum: iOS 11.0. Required frameworks include AdSupport, StoreKit, UserNotifications, AVFoundation, ImageIO.

## CI/CD

CircleCI 2.1 with workflows:
- **un-tagged-build**: test → build → auto-tag (on every non-tag commit)
- **tagged-build**: test → build → deploy to S3 (versioned) + update teak-ios-framework repo, then hold for latest S3 deploy + CocoaPods trunk publish
- **nightly**: scheduled on `develop` and `master`

Artifacts deployed to `s3://teak-build-artifacts/ios/` with SHA512 checksums.

## Version Management

Git tags are the single source of truth for versioning. There are no version-bearing files to keep in sync.

- **Build-time**: Xcode "Define Version" build phases run `git describe --tags` and write `Teak/TeakVersion.h` to `$(DERIVED_FILE_DIR)`. This header defines `TEAK_SDK_VERSION` used in API payloads.
- **CI artifact naming**: CircleCI deploy jobs use `git describe --tags` for S3 artifact paths.
- **Tagging**: The `teak/tag-promote` CI orb parses the HEAD commit message for "Promote to: X.Y.Z" and creates + pushes a git tag.

### Release Flow

```
# Optionally create docs/modules/changelog/versions/X.Y.Z.yaml with release notes
git commit -m "Promote to: X.Y.Z"
git push
# CI: orb detects commit message → tags → tagged-build workflow
# deploy_versioned: uploads to S3 + updates teak-ios-framework repo (commit, tag, push)
# hold: manual approval gate
# deploy_latest: uploads "latest" to S3
# publish_pod: pod trunk push to CocoaPods registry
```

**Version numbers are immutable.** Once a promote commit is pushed and CI tags it, that version is permanently consumed. Tags cannot be moved or reused. When promoting, always check recent commit messages (e.g., `git log --oneline`) to determine the next available version number. Tags are created remotely by CI, so `git tag --list` requires a fetch first and is less reliable than checking the log.

## Branches

We follow git-flow (mostly). Currently the following branches are active.

- 4.3-stable: Ongoing development work for the 4.3.x SDK series
- develop: Ongoing development work for the next major SDK update (4.4 or 5)

Currently main/master is unused. Requires architectural discussion.

When creating bugfix or feature branches, use the base branch for the release the work will be included in.

## Commit Message Format

Every commit must include a full human-Claude interaction log. Placeholders
below are in angle brackets — replace them with actual content, do not include
the brackets. The interaction log only covers prompts since the previous commit,
not the entire session.

```
Brief description of what was done

Technical description of changes made

## Human-Claude Interaction Log

### Human prompts (VERBATIM - include typos, informal language, COMPLETE text):
**Include EVERY prompt since last commit - even short ones, corrections, clarifications**
1. "<copy-paste ENTIRE first prompt since last commit>"
   → Claude: <what Claude did in response>

2. "<copy-paste ENTIRE second prompt>"
   → Claude: <how Claude adjusted>

<continue numbering ALL prompts - don't skip any or judge importance>

### Key decisions made:
- Human guided: <specific guidance provided>
- Claude discovered: <patterns found>

🤖 Generated with Claude Code
Co-Authored-By: Claude <noreply@anthropic.com>
```
