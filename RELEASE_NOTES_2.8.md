# PlayStatus 2.8 Release Notes

## Scope
- Baseline: `v2.7` (`73cbf2e8ef559e181d5dec8b8e36bbf593659cd5`).
- Target: local `master` `HEAD` (`706d5e78e4e1a0323301c996930d20ae294083a6`).
- Change window: 47 non-merge commits from 2024-05-14 to 2026-02-24.
- This document is a high-level summary of user-facing changes plus one migration note.

## Major Changes
- Replaced the legacy AppKit codebase with a SwiftUI implementation for the menu bar app.
- Redesigned the now-playing popover with improved regular and mini mode behavior.
- Expanded lyrics support with faster fetch logic, better fallbacks, and improved interaction design.
- Improved playback reliability across Apple Music and Spotify, including metadata and control fixes.
- Refined animation quality, layout behavior, dark mode handling, and visual assets.
- Updated licensing from Apache 2.0 to MIT.

## Lyrics and Search Improvements
- Added a stronger LRCLIB lyrics pipeline with better request flow, faster retries, and parallel lookups.
- Improved lyrics fetch handling to reduce failed states and make fallback behavior more reliable.
- Added a mini lyrics toggle panel and tuned mini lyrics expand/collapse transition timing.
- Fixed lyrics pane resize issues and synchronized lyrics/artwork/popover transition timing.
- Added a direct LRCLIB action in the interface and cleaned up lyrics panel presentation details.
- Implemented provider-aware search handoff so search actions are routed to the right music source.
- Fixed Apple Music search and play behavior for better consistency in in-app control flows.

## Playback, Providers, and Reliability
- Fixed Spotify metadata synchronization to improve track info consistency.
- Improved Apple Music playback actions and fixed control-path edge cases.
- Fixed playback controls behavior and improved command reliability in the popover.
- Updated status-bar interaction to trigger the status toggle on mouse down for faster response.
- Fixed status bar popover layout issues and stabilized interaction behavior under frequent updates.

## UI/UX and Visual Updates
- Added smoother mini-to-regular and regular-to-mini transitions with cleaner crossfades and less jitter.
- Tuned popover resizing animation and synchronized artwork timing during mode changes.
- Improved marquee presentation with spacing adjustments and cleaner help overlay behavior.
- Fixed dark mode and layout issues across settings and popover views.
- Added artwork animation options and refined visual motion behavior.
- Refreshed provider iconography with updated Spotify and Apple Music glyph assets.
- Updated app icon assets and settings icon visuals.

## Settings and System Controls
- Fixed settings view activation issues so settings open more reliably.
- Improved settings/help copy and organization for key controls.
- Kept Sparkle update actions integrated in settings, including "Check for Updates" behavior.
- Added audio output controls, including output device selection, volume adjustment, and mute support.
- Added persistent media cache support to reduce repeated lookup work and improve perceived responsiveness.

## Under the Hood (Migration Note)
- The old storyboard/AppDelegate/controller stack was removed and replaced with SwiftUI app entry, views, and state-driven model logic.
- Playback/provider wiring was reorganized into dedicated provider and model layers for Apple Music and Spotify.
- New internal subsystems were introduced for lyrics orchestration, persistent media caching, status bar control, and Sparkle updater integration.
- Public interfaces/types impact: no external or public API contract changes were introduced by this release-note scope.
- User-facing interface impact is documented above under popover behavior, lyrics/search, settings/system controls, and update flow.

## Compatibility and Update Path
- Sparkle update continuity is preserved, including the existing appcast feed/update flow used by installed builds.
- This release is intended as the upgrade path from `v2.7` users on the legacy codebase to the SwiftUI-based app experience.
- Apple Music and Spotify remain supported providers, with improved handoff and metadata behavior.
- License in this codebase is MIT.
