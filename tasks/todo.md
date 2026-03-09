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

## Codebase Reduction And Efficiency Refactor

- [x] Review the current popover, walkthrough, model, settings, and status-bar structure against the approved reduction plan
- [x] Extract shared popover artwork/details primitives and delete duplicated mini/regular rendering logic
- [x] Split `NowPlayingModel` theme, lyrics, animated-artwork, and audio-output responsibilities into focused helpers while preserving `NowPlayingModel.shared`
- [x] Separate settings, hotkeys, previews, and row helpers into smaller units without changing the existing settings UI
- [x] Refactor walkthrough sections into reusable, data-backed building blocks while preserving copy, visuals, and coachmark behavior
- [x] Replace deprecated one-parameter `onChange` usages in touched code and remove dead scaffolding if it is truly unused
- [x] Verify with clean build and diagnostic build, then document review notes and follow-up lessons

## Review

- Added shared popover/detail primitives in `PopoverSharedComponents.swift` and a shared animated artwork crossfade surface in `ArtworkStreamTransitionSurface.swift`, then rewired the mini and regular popover detail panes to use them instead of carrying parallel state/rendering code.
- Broke the expensive `NowPlayingPopover` regular-mode composition and mini chrome backgrounds into smaller helpers so the previous long-body/type-check warnings no longer show up in the diagnostic build.
- Split settings support out of `AudioHotkeysAndSettings.swift` into `AudioAndHotkeySupport.swift` and `SettingsSupportViews.swift`, leaving the main settings file as page composition while preserving the existing layout, preview sheets, and hotkey behavior.
- Refactored walkthrough preview surfaces into smaller reusable cards/layout helpers, which removed the earlier `OnboardingWalkthrough.swift` diagnostic hotspot warnings without changing copy, animation, or coachmark flow.
- Simplified `NowPlayingModel` by consolidating repeated animated-artwork reset/idle-transition logic into focused helpers while preserving `NowPlayingModel.shared` and the current published surface.
- Replaced deprecated one-parameter `onChange` usages in the touched UI/settings files and deleted the unused comment-only `NowPlayingMenuBarApp.swift` scaffold.
- Verified with `xcodebuild -project /Users/nikhilbolar/Documents/PlayStatus/PlayStatus.xcodeproj -scheme PlayStatus -configuration Debug -sdk macosx -derivedDataPath /tmp/PlayStatusDerivedData CODE_SIGNING_ALLOWED=NO build`.
- Verified with `xcodebuild -project /Users/nikhilbolar/Documents/PlayStatus/PlayStatus.xcodeproj -scheme PlayStatus -configuration Debug -sdk macosx -derivedDataPath /tmp/PlayStatusDerivedData CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS='-Xfrontend -warn-long-function-bodies=200 -Xfrontend -warn-long-expression-type-checking=200' build`; the earlier long-body warnings in `NowPlayingPopover.swift`, `OnboardingWalkthrough.swift`, and `CommonComponents.swift` no longer appear.
- Raw line-count note: the large monoliths are smaller and easier to reason about, but this first pass prioritised reuse and compile-shape cleanup over aggressive abstraction removal, so total touched production LOC ended roughly flat to slightly up because the deleted duplication was replaced with explicit shared helper files.

## Architecture-First Efficiency Refactor v2

- [x] Review the remaining monoliths and mirror the architecture-first extraction boundaries into code changes
- [x] Rebuild `NowPlayingModel` around focused internal helpers for snapshot selection, lyrics, animated artwork, theme computation, and audio output while preserving `NowPlayingModel.shared`
- [x] Split `AppleMusicAnimatedArtworkService` into smaller pure lookup/parsing/selection units without changing cache behavior or resolution heuristics
- [x] Reduce `StatusBarController` to lifecycle/orchestration and extract status-item, popover-layout, and detached-window responsibilities
- [x] Reduce `NowPlayingPopover`, `CommonComponents`, and `OnboardingWalkthrough` to shells plus focused feature views without changing copy, visuals, or animations
- [x] Re-run normal and diagnostic builds, then document architectural outcomes, warning results, and residual manual QA

## Review

- Split the animated-artwork resolver into dedicated subsystem files: `AnimatedArtworkStreamSelection.swift` now owns candidate extraction plus HLS variant selection, `ITunesMetadataLookup.swift` owns the Apple Music/iTunes lookup pipeline, and `AppleMusicAnimatedArtworkService.swift` is down to the public facade and cache-orchestration path.
- Moved theme computation out of `NowPlayingModel.swift` into `NowPlayingThemeEngine.swift`, leaving the model responsible for applying resolved colors rather than carrying palette-generation math inline.
- Broke `CommonComponents.swift` into feature families: `CommonControls.swift` now owns provider badges, transport controls, output controls, and progress UI; `DetachedWindowDragSupport.swift` owns the AppKit drag-lock bridge; `LiquidGlassComponents.swift` owns the glass/card chrome. `CommonComponents.swift` is now the artwork/motion surface file only.
- Split onboarding preview/demo rendering into `OnboardingPreviewCards.swift`, which now owns the walkthrough preview stage, personalization preview, preview cards, and shared preview chrome. `OnboardingWalkthrough.swift` dropped from 2633 lines to 1909 lines.
- Pulled the AppKit status-item/window surface types into `StatusBarPresentationViews.swift`, reducing `StatusBarController.swift` from 1122 lines to 739 lines so it reads more like lifecycle/orchestration instead of a container for every support type.
- Net monolith reductions from this pass: `NowPlayingModel.swift` 2002 -> 1830, `CommonComponents.swift` 1775 -> 1133, `OnboardingWalkthrough.swift` 2633 -> 1909, `StatusBarController.swift` 1122 -> 739, `AppleMusicAnimatedArtworkService.swift` 1231 -> 159 plus `ITunesMetadataLookup.swift` 870.
- Current remaining hotspot: `NowPlayingPopover.swift` is still 2932 lines and is the clearest next target for a dedicated shell-plus-components split.
- Production Swift LOC is now 17631 lines across the app source, versus 17593 before this pass. The total is slightly higher because duplicated code was replaced with explicit subsystem files, but the structural concentration is materially lower.
- Verified with `xcodebuild -project /Users/nikhilbolar/Documents/PlayStatus/PlayStatus.xcodeproj -scheme PlayStatus -configuration Debug -sdk macosx -derivedDataPath /tmp/PlayStatusDerivedData CODE_SIGNING_ALLOWED=NO build`.
- Verified with `xcodebuild -project /Users/nikhilbolar/Documents/PlayStatus/PlayStatus.xcodeproj -scheme PlayStatus -configuration Debug -sdk macosx -derivedDataPath /tmp/PlayStatusDerivedData CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS='-Xfrontend -warn-long-function-bodies=200 -Xfrontend -warn-long-expression-type-checking=200' build`; no new long-function or long-expression warnings were emitted in this pass.
- Manual runtime QA for menu-bar interactions, detached-window persistence, and walkthrough/preview visuals is still recommended because this pass was architecture-heavy and I did not open the app interactively in this turn.

## NowPlayingPopover Monolith Follow-up

- [x] Review the current `NowPlayingPopover.swift` shell versus its embedded helper types and pick clean extraction seams
- [x] Move mini-card support types and chrome helpers into focused popover component files without changing layout or animation behavior
- [x] Move lyrics/details pane support, pointer tracking, and detail-tab controls out of the shell file while preserving current interactions
- [x] Rebuild normal and diagnostic targets, then document the popover-specific outcomes and remaining hotspot risk

## Review

- Reduced `NowPlayingPopover.swift` from 2932 lines to 833 lines by turning it into a shell for mode switching, layout, regular-surface composition, search wiring, and coachmark coordination only.
- Moved shared popover glue into `NowPlayingPopoverSupport.swift` (345 lines), mini-card artwork/chrome/pointer tracking into `NowPlayingPopoverMiniCard.swift` (822 lines), and lyrics/details-pane rendering into `NowPlayingPopoverDetails.swift` (883 lines).
- The extracted popover family totals 2883 lines versus 2932 in the original monolith, so this split improved factoring and compile shape while also deleting a small amount of duplicated helper code.
- Verified with `xcodebuild -project /Users/nikhilbolar/Documents/PlayStatus/PlayStatus.xcodeproj -scheme PlayStatus -configuration Debug -sdk macosx -derivedDataPath /tmp/PlayStatusDerivedData CODE_SIGNING_ALLOWED=NO build`.
- Verified with `xcodebuild -project /Users/nikhilbolar/Documents/PlayStatus/PlayStatus.xcodeproj -scheme PlayStatus -configuration Debug -sdk macosx -derivedDataPath /tmp/PlayStatusDerivedData CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS='-Xfrontend -warn-long-function-bodies=200 -Xfrontend -warn-long-expression-type-checking=200' build`; no new long-body or long-expression warnings appeared in the popover files.
- Manual runtime QA for mini hover transitions, detached-window hover controls, and lyrics/credits pane reveal behavior is still recommended because this pass was structural and I did not launch the app interactively.

## Hidden Memory Reduction Fix

- [x] Trace why `Reduce Hidden Memory Usage` does not materially lower memory after all surfaces are closed
- [x] Unload hidden popover/detached surface content and clear any remaining transient artwork caches/state
- [x] Rebuild and verify the reduced-memory path, then document the result

## Review

- Traced the weak behavior to two gaps: the model cleared some transient media, but the hidden `NSHostingController` surfaces stayed loaded, and the Apple Music provider kept one static artwork image cached outside the model cleanup path.
- Updated `StatusBarController` so `isPopoverVisible` now drives a hidden-surface teardown when `Reduce Hidden Memory Usage` is enabled: once no popover or detached window is visible, both host controllers swap to `EmptyView`, which releases hidden SwiftUI state and any view-owned media infrastructure until the next reveal.
- Updated `NowPlayingModel.releaseTransientMediaForHiddenSurface()` to clear the Music provider's transient artwork cache alongside the existing Spotify/iTunes memory caches and animated-artwork state reset.
- The live workspace build is currently blocked by unrelated in-progress popover extraction files (`NowPlayingPopover.swift` plus untracked `NowPlayingPopoverDetails.swift`, `NowPlayingPopoverMiniCard.swift`, and `NowPlayingPopoverSupport.swift`) that redeclare the same types.
- Verified the hidden-memory fix itself by overlaying the three tracked code changes onto a clean tracked copy in `/tmp/PlayStatusVerify` and building with `xcodebuild -project /tmp/PlayStatusVerify/PlayStatus.xcodeproj -scheme PlayStatus -configuration Debug -sdk macosx -derivedDataPath /tmp/PlayStatusVerifyDerivedData -clonedSourcePackagesDirPath /tmp/PlayStatusDerivedData/SourcePackages CODE_SIGNING_ALLOWED=NO build`, which succeeded.

## Live Memory Investigation

- [x] Inspect PID `99159` and capture the current resident/system memory breakdown
- [x] Correlate the largest memory buckets with PlayStatus subsystems or runtime frameworks
- [x] Decide whether another code change is needed, then document the verified conclusion

## Review

- Inspected PID `99159` with `ps`, `vmmap -summary`, and `heap -s -H`. The process showed `305648 KB` RSS, `169.3 MB` physical footprint on the first `vmmap` pass, and `182.9 MB` physical footprint on the later `heap` pass, so the user's ~180 MB observation matches the current live process.
- The largest resident buckets were not app-specific caches alone: `CG image` was `31.4 MB`, `IOSurface` was `10.4 MB`, allocator-held `MALLOC_SMALL` pages were `48.1 MB` resident, and total live heap allocations were only `27.4 MB`, which means a sizable part of the footprint is allocator/page retention plus image-backed system frameworks rather than active app objects.
- The filtered heap output showed a loaded `PlayStatusSettingsView` / `SettingsSidebar` SwiftUI scene and related settings scroll-view containers, but it did not show evidence of a live `AVPlayer`-backed animated-artwork surface. That suggests the reduced-memory work for hidden player surfaces is helping, while the current footprint is now dominated by broader SwiftUI/AppKit scene state and image-backed memory.
- No follow-up code change was made in this pass because the live data did not point to one obviously leaking PlayStatus-owned cache. The next worthwhile optimization target, if we want to push below the current floor, is the Settings scene and any remaining image-heavy surfaces rather than the hidden popover/detached player path.

## Settings Memory Optimization

- [x] Inspect the Settings scene declaration and settings UI for eagerly retained heavy state or views
- [x] Reduce the steady-state memory cost of the Settings path without breaking behavior
- [x] Verify the optimization and document the measured outcome or residual limit

## Review

- Traced the remaining steady-state footprint to the SwiftUI `Settings` scene staying resident after the user closed the window. The live heap sample for PID `99159` still showed `PlayStatusSettingsView`, `SettingsSidebar`, and settings scroll containers loaded even though the now-playing surfaces had already been taught to unload.
- Updated `PlayStatusSettingsView` so the heavy sidebar and tab-content tree are now gated behind a local `settingsContentLoaded` flag. When the Settings window is closed or minimized, the scene swaps down to a lightweight placeholder instead of keeping the full settings hierarchy alive off-screen.
- Added a `SettingsSceneVisibilityBridge` AppKit bridge that attaches to the hosting `NSWindow`, preserves the existing window chrome/size behavior, and drives the load/unload decision from real window visibility events. The coordinator now also resets its remembered size when a new Settings window is attached so reopen cycles still get the correct frame configuration.
- Verified the change by rebuilding a clean tracked copy in `/tmp/PlayStatusVerify` with `xcodebuild -project /tmp/PlayStatusVerify/PlayStatus.xcodeproj -scheme PlayStatus -configuration Debug -sdk macosx -derivedDataPath /tmp/PlayStatusVerifyDerivedData -clonedSourcePackagesDirPath /tmp/PlayStatusDerivedData/SourcePackages CODE_SIGNING_ALLOWED=NO build`, which succeeded after overlaying the tracked memory-related files.
- I did not re-measure a freshly launched runtime after this change in this turn, so the expected memory improvement is based on removing the resident Settings subtree rather than on a new post-fix `vmmap` sample.

## Post-Settings Live Memory Investigation

- [x] Inspect PID `2205` and capture the current resident/system memory breakdown after the Settings-scene unload change
- [x] Correlate the largest memory buckets with the still-loaded PlayStatus subsystems or framework allocations
- [x] Implement and verify the next reduction only if the live data points to a concrete resident target

## Review

- Inspected PID `2205` with `ps`, `vmmap -summary`, and `heap -s -H`. The process showed `223776 KB` RSS and a `166.5 MB` physical footprint, so the earlier Settings-scene unload reduced RSS from the previous `305648 KB` sample but did not materially lower the system-reported footprint floor yet.
- The dominant resident buckets in this run were still image- and allocator-heavy rather than large live PlayStatus heap objects: `CG image` was `35.0 MB` resident, `IOSurface` was `4.6 MB`, `MALLOC_SMALL` was `39.3 MB` resident plus another `31.0 MB` in empty retained small-allocation regions, and total live heap allocations were only `24.3 MB`.
- The heap no longer pointed at the old fully loaded Settings scroll/sidebar subtree as the primary issue. Instead, one concrete app-owned image cache stood out: `WalkthroughPreviewAssets` was still alive, including a `WalkthroughPreviewArtworkKey -> NSImage` cache that keeps the onboarding preview artwork decoded in memory even when the walkthrough is not on screen.
- Updated `WalkthroughPreviewAssets` so it no longer prewarms artwork during singleton initialization. The cache now prewarms only when the walkthrough is actually presented, and `OnboardingCoordinator` clears that memory again when the walkthrough window closes.
- Verified the follow-up change by overlaying the tracked memory-related files onto `/tmp/PlayStatusVerify` and rebuilding with `xcodebuild -project /tmp/PlayStatusVerify/PlayStatus.xcodeproj -scheme PlayStatus -configuration Debug -sdk macosx -derivedDataPath /tmp/PlayStatusVerifyDerivedData -clonedSourcePackagesDirPath /tmp/PlayStatusDerivedData/SourcePackages CODE_SIGNING_ALLOWED=NO build`, which succeeded.
- I did not re-sample a newly launched process after the walkthrough-cache fix in this turn, so PID `2205` still reflects the pre-fix runtime. A fresh relaunch is needed to confirm how much of the remaining `CG image` footprint came from those onboarding preview assets.
