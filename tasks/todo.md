# PlayStatus Relaunch Walkthrough

- [x] Review current app entry points, popover controls, and existing dirty changes
- [x] Add onboarding coordinator/state persistence and window presentation
- [x] Build fresh-install and upgrade walkthrough UI with demo-backed previews
- [x] Wire settings and app commands to replay the walkthrough
- [x] Add contextual coachmarks for popover and settings discovery
- [x] Verify behavior with build/test pass and document results

## Walkthrough Polish Follow-up

- [x] Reset walkthrough scroll position to the top whenever the current step changes
- [x] Make walkthrough interactions read as clickable with clearer affordances and navigation
- [x] Rebuild and relaunch the debug app for walkthrough retesting
- [x] Document the follow-up verification and polish notes

## Coachmark Placement Follow-up

- [x] Move the settings navigation coachmark so it no longer overlays or blocks the sidebar items
- [x] Rebuild and relaunch the debug app for coachmark retesting
- [x] Document the placement fix and verification result

## Walkthrough Performance Rewrite

- [x] Raise the app deployment target to macOS 15.0
- [x] Add walkthrough draft/session state and preview asset caching so the walkthrough stops observing the live shared model
- [x] Simplify the walkthrough visuals and preview rendering for responsiveness
- [x] Rebuild, retest the walkthrough path, and document the performance rewrite

## Walkthrough Settings Action Fix

- [x] Trace the walkthrough Settings action through the actual Settings scene opening path
- [x] Replace the dead selector-based walkthrough action with SwiftUI's native settings opener
- [x] Rebuild and relaunch the debug app for walkthrough retesting
- [x] Document the regression fix

## Walkthrough Step-Lag Follow-up

- [x] Trace the remaining Continue-button lag through the walkthrough transition and draft-commit path
- [x] Reorder step transitions so the UI advances before shared-model side effects run
- [x] Tighten the step animation timing and rebuild/relaunch for retesting
- [x] Document the cause and fix

## Walkthrough Step-Animation Scope Fix

- [x] Trace the remaining lag between the first two steps to step-wide animation scope
- [x] Limit animation to the content swap and stop animating the backdrop on every step change
- [x] Rebuild and relaunch the debug app for retesting
- [x] Document the follow-up fix

## Instant Walkthrough Navigation Rewrite

- [x] Simplify walkthrough navigation architecture so the shell stays stable and page swaps are instant
- [x] Remove heavy preview surfaces from the welcome/connect steps and reserve rich previews for Explore
- [x] Stop applying walkthrough draft state during navigation; only commit on Open Settings and Finish
- [x] Rebuild, relaunch, and verify rapid Welcome <-> Connect navigation plus walkthrough behaviors
- [x] Document the navigation rewrite and capture the new lesson

## Review

- Added a new onboarding coordinator plus walkthrough window for fresh installs and returning-user update tours.
- Wired replay entry points into the app menu and Settings, then added coachmarks to the popover and settings sidebar.
- Fixed the walkthrough layout so two-column steps fall back cleanly, preview stages stack when needed, and the main body scrolls instead of clipping.
- Fixed walkthrough readability by treating the light content surfaces as light-mode cards, increasing surface opacity, and restoring dark text contrast inside the setup forms and instructional pills.
- Fixed walkthrough flow polish so each step snaps back to the top on navigation, and made the walkthrough's custom interactive surfaces feel clickable with sidebar step navigation plus stronger hover states on chips and action cards.
- Fixed the settings navigation coachmark so it now sits inline beneath the sidebar tabs instead of overlaying and blocking the navigation items it is trying to explain.
- Reworked the walkthrough around a dedicated `WalkthroughDraftState` so onboarding no longer observes the shared live playback model while provider polling, marquee updates, or now-playing refreshes continue in the background.
- Added `WalkthroughPreviewAssets` caching plus lighter static preview cards and a `MeshGradient` backdrop so demo artwork is pre-rendered once and the walkthrough avoids the old blurred crossfade background path.
- Raised the minimum supported macOS version to 15.0 so the walkthrough can use newer SwiftUI animation and background APIs with simpler availability handling.
- Fixed the walkthrough's "Open Settings" actions so they now use SwiftUI's `openSettings` environment action instead of the older `showSettingsWindow:` selector path, while still committing the draft onboarding state first.
- Fixed the remaining step-change lag by moving draft commits off the critical tap path: the walkthrough now advances to the next step first, then flushes shared-model updates on the next main-actor turn so provider refreshes and launch-item work do not block the transition.
- Fixed another source of lag in the first two steps by removing the global animated `currentStep` transaction. The content pane now animates locally while the `MeshGradient` backdrop and other step-wide surfaces update without animation.
- Rewrote the walkthrough around a single stable shell with per-step local scroll views and a tiny content-pane opacity transition, so page navigation no longer depends on a shared `ScrollViewReader`, a shared root scroll position, or step-wide background swaps.
- Simplified the welcome and upgrade pages to use lightweight hero cards instead of rich preview stages, and removed the stale duplicate walkthrough implementation that was still living lower in `OnboardingWalkthrough.swift`.
- Reworked the personalize-step preview so it now reads like a settings preset summary instead of another oversized mini-player mockup: the card uses one balanced theme hero plus compact summary tiles for display mode, artwork motion, and launch behavior.
- Verified the rewritten path builds successfully with `xcodebuild -project PlayStatus.xcodeproj -scheme PlayStatus -configuration Debug -sdk macosx -derivedDataPath /tmp/PlayStatusDerivedData CODE_SIGNING_ALLOWED=NO build` and relaunched `/tmp/PlayStatusDerivedData/Build/Products/Debug/PlayStatus.app`.
- Verified with `xcodebuild -project PlayStatus.xcodeproj -scheme PlayStatus -configuration Debug -sdk macosx -derivedDataPath /tmp/PlayStatusDerivedData CODE_SIGNING_ALLOWED=NO build`.
- Build succeeded and the debug app launched from `/tmp/PlayStatusDerivedData/Build/Products/Debug/PlayStatus.app`. Manual runtime QA of walkthrough responsiveness, permission prompts, and coachmark placement is still recommended.
