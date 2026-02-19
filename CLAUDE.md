# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Teak iOS SDK — an Objective-C framework providing push notifications, deep linking, rewards, and analytics for free-to-play mobile games. Published as a CocoaPod (`Teak`) and as pre-built xcframeworks.

## Build & Test Commands

**Build the framework:**
```bash
./compile
```
This runs xcodebuild for the `Framework` target (Release, iphoneos), runs clang static analysis, builds the Sample app extensions via fastlane, and zips artifacts.

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
- SDK source headers via relative paths: `#import "../../Teak/TeakPushState.h"`
- Framework public headers: `#import <Teak/Teak.h>`
- To access internal properties, re-declare them in a class extension in the test file rather than importing `Teak+Internal.h` (which pulls in headers not on the test target's search path)

**Test patterns:**
- `DebugConfigurationTests.m` — dependency injection with real objects (preferred when possible)
- `LogTests.m` — OCMockito mocking with `mock()`, `given()`, `stubProperty()`, `assertThat()`
- `NotificationSettingsTests.m` — mocking with NSInvocationOperation for async-pattern methods

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
- `TeakExtensions/` — Scripts and sources for integrating notification extensions into customer apps (`add_teak_extensions.rb`)

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
- **tagged-build**: test → build → deploy to S3 (versioned), then hold for latest deploy
- **nightly**: scheduled on `develop` and `master`

Artifacts deployed to `s3://teak-build-artifacts/ios/` with SHA512 checksums.

## Version Management

Current version lives in the `VERSION` file (currently 4.3.2). The `release` script creates a git tag from this file.

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

