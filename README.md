#![playstatus_header](https://user-images.githubusercontent.com/45484873/56880861-09cb3980-6a67-11e9-9d45-037a9165b212.png)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Version: 2.8](https://img.shields.io/badge/Version-2.8-green.svg)](https://github.com/nbolar/PlayStatus/releases)
[![Platform](https://img.shields.io/badge/macOS-15%2B-black.svg)](https://developer.apple.com/macos/)
[![Built with SwiftUI](https://img.shields.io/badge/UI-SwiftUI-orange.svg)](https://developer.apple.com/xcode/swiftui/)

PlayStatus is a native SwiftUI macOS menu bar app for controlling Apple Music and Spotify without living in a full desktop window all day. The current generation of the app is a full SwiftUI relaunch with a richer now-playing surface, better onboarding, customizable display themes, provider-aware search, lyrics and credits, a detached floating player, and a cleaner settings flow.

## Why this version feels different

- The old AppKit utility-style player has been replaced with a layered SwiftUI player that supports regular, mini, and detached modes.
- New users get a guided walkthrough, and existing users can replay the full tour or the shorter "What's New" tour at any time.
- Lyrics, credits, and provider-aware search now live inside the main player instead of feeling like separate utility flows.
- Display tuning is much deeper: menu bar text modes, detached window sizing, theme presets, animated artwork, artwork motion styles, and progress-strip options all live in Settings.
- The app is more efficient when closed: media caches, onboarding previews, and heavy Settings surfaces can unload when they are not visible.

## What the app looks like now

### Regular player

<img width="556" height="280" alt="Image" src="https://github.com/user-attachments/assets/a47cade8-7157-44a3-b5c8-cc6fae184ef0" />

#### Lyric View
<img width="556" height="521" alt="Image" src="https://github.com/user-attachments/assets/741a481e-7389-4282-a43b-ed0a916c4e74" />

### Mini player

<img width="406" height="406" alt="Image" src="https://github.com/user-attachments/assets/c90a57cc-caa3-4800-8522-b4283bddb570" />

#### Lyric View
<img width="406" height="586" alt="Image" src="https://github.com/user-attachments/assets/ace27ca0-f0b2-47d8-8981-9f59a3a616fd" />


### Settings

<img width="780" height="742" alt="Image" src="https://github.com/user-attachments/assets/ed84d8a9-10c8-48ce-921d-c55404165803" />


## First launch

1. Download the latest [release](https://github.com/nbolar/PlayStatus/releases/latest/) and move PlayStatus to `/Applications`.
2. Launch the app and choose which providers PlayStatus should listen to: Apple Music, Spotify, or both.
3. When macOS asks for Automation permission, allow PlayStatus to control Music and/or Spotify.
4. If no prompt appears, retry once and then check `System Settings -> Privacy & Security -> Automation`.
5. Use the walkthrough to set your preferred provider, display mode, theme, animated artwork, and launch-at-login behavior before closing the window.

## How people use PlayStatus day to day

### 1. Open the player from the menu bar

- Click the menu bar item to open the main player.
- Choose a menu bar display style in `Settings -> Display`: `Artist`, `Song`, `Artist + Song`, or `Icon Only`.
- Long titles can scroll, and title transitions can animate when tracks change.

### 2. Pick the right player surface

- `Regular mode` is the full player with artwork, inline search, progress, transport controls, lyrics, and credits.
- `Mini mode` is a calmer, more compact surface with quick controls and optional mini lyrics/credits.
- `Detached mode` turns the player into a floating standalone window. You can keep it always on top and choose `Small`, `Medium`, or `Large`.

### 3. Control playback quickly

- Use the transport controls for previous, play/pause, and next.
- Click the track title to jump straight into the source app.
- If Apple Music is the active source, you can favorite the current track from the player.
- The playback progress bar is seekable, and the menu bar can show a separate progress strip.

### 4. Use lyrics, credits, and search where they matter

- `Lyrics` and `Credits` open from the player instead of in separate utility views.
- Lyrics can come from Apple Music or LRCLIB depending on availability.
- Search is provider-aware:
  - Spotify opens the matching Spotify search.
  - Apple Music searches your Music library and can play a matching result.
- The mini player has its own quick lyrics and credits toggles.

### 5. Personalize the visual feel

- Theme presets: `Artwork Adaptive`, `Frosted`, `Midnight`, `Warm Studio`, `High Contrast`, `Graphite`.
- Animated artwork can use static motion, and supported tracks can use animated editorial streams.
- Artwork motion styles: `Parallax by Pointer`, `Vinyl Spin`, `Film Grain Drift`.
- Non-adaptive themes let you blend album colors back into the surface.

## Settings guide

### Display

- Menu bar text mode
- Parenthetical-title cleanup
- Scrollable titles
- Slide animation on track change
- Detached window always-on-top
- Detached window size preset
- Title width
- Artwork color intensity
- Theme selection
- Album color blend
- Animated artwork and animated artwork streams
- Animated stream quality and preview
- Artwork motion style preview

### Playback

- Preferred provider: `Auto`, `Music`, or `Spotify`
- Automatic provider priority when the preferred app is idle
- Enable or disable Apple Music and Spotify independently
- Expand the details pane automatically for new tracks

### Hotkeys

Global shortcuts are configurable in `Settings -> Hotkeys`. Default bindings are:

| Action | Default |
| --- | --- |
| Play/Pause | `Ctrl+Opt+Cmd+P` |
| Next Track | `Ctrl+Opt+Cmd+N` |
| Previous Track | `Ctrl+Opt+Cmd+B` |
| Toggle Popover | `Ctrl+Opt+Cmd+O` |
| Toggle Favorite | `Ctrl+Opt+Cmd+L` |
| Toggle Detached Mode | `Ctrl+Opt+Cmd+D` |

### System

- Replay the full walkthrough
- Open the shorter `What's New` tour
- Temporarily re-arm `Debug Coachmarks` for QA or troubleshooting
- Launch at login
- Check for updates through Sparkle
- Clear the local media cache
- Reduce hidden memory usage when all surfaces are closed

### License

- MIT license text
- LRCLIB attribution and disclaimer for third-party lyrics

## Walkthrough and onboarding

The new SwiftUI version includes a dedicated walkthrough window for both first-run setup and returning-user upgrades.

- `Show Walkthrough` is also available from the app menu with `Cmd+Shift+/`.
- The full walkthrough helps with provider setup, Automation permissions, personalization, and hotkeys.
- The shorter `What's New` flow highlights the redesigned player, integrated lyrics/search, and the reorganized Settings experience.
- Contextual coachmarks can teach the search button, mode toggle, detached mode, detail toggles, and Settings navigation.

## Privacy, network use, and caching

- PlayStatus uses AppleScript to control Apple Music and Spotify, so macOS Automation permission is required.
- Lyrics may be fetched from LRCLIB, and artwork or animated artwork lookups may use public Apple/iTunes endpoints when needed.
- The media cache stores lyrics and artwork locally on your Mac and caps itself at 50 MB.
- Lyrics are third-party content and may be incomplete or unavailable.

## Compatibility

- Minimum supported macOS version: `15.0`
- Supported providers: `Apple Music`, `Spotify`
- Update flow: Sparkle-based in-app update checks remain supported
- License: `MIT`

