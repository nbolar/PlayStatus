# PlayStatus 3.1.2

Your paused song can keep its place in the menu bar, PlayStatus uses a fraction of the CPU it used to, it no longer freezes when Music is busy, the menu bar controls work again on macOS 27, and two crashes are fixed.

## New

- **Paused songs can stay in the menu bar.** Pausing used to collapse the title and leave only the icon, so there was no way to see what Play would resume without opening the player. With **Show title when paused** on, the title stays in place. It's dimmed and holds still instead of scrolling, so you can tell paused from playing at a glance. Stopping playback, or quitting the player, still clears it. New installs have it on; if you're updating, your menu bar keeps behaving the way you're used to until you turn it on in `Settings → Menu Bar`.
- **Dim the artist.** With the menu bar set to **Artist + Song**, the artist can now be drawn quieter than the song title, so the part you glance for stands out. Turn it on in `Settings → Menu Bar`.
- **What's New after an update.** Updating now opens a short summary of what changed, instead of the full walkthrough. **Release Notes…** in the app menu lists every version's notes, with the ones you haven't read marked. The walkthrough is still in the app menu and Settings whenever you want it.

## Improved

- **No more Play button that does nothing.** When Music is showing an Apple Music catalog page — Listen Now, Browse, a search result — its play command silently does nothing, and the idle player's **Play in Music** button looked live while doing exactly that. The player now says Music has nothing queued and offers **Shuffle Library** instead. If a Play still doesn't start anything, the button checks again a moment later and corrects itself.
- **Menu bar controls that know what works.** The previous / play-pause / next buttons now hide when no player is running, rather than showing three dead controls. When a player is open but idle, Play stays available and the skip buttons grey out, since there's no track to skip. They also react straight away when Music or Spotify launches or quits.
- **Far less CPU at rest.** PlayStatus kept working after you closed the player. The menu bar title was being redrawn by macOS the slow way, and the player itself carried on drawing every frame out of sight — a progress bar animating for nobody. Both are fixed. With a song playing and the player closed, PlayStatus now uses about 0.5% of a CPU core, measured against 9% before.
- **Never stuck waiting on your player.** Play, pause, skip and seek were sent to Music or Spotify from the same thread that draws the menu bar, with no time limit on the reply. A player that was busy, or stuck on a slow network, could take PlayStatus down with it — in the worst case for the two minutes macOS allows. Commands now go out on their own, in the order you pressed them, and anything the player hasn't answered within ten seconds is given up on.
- **Smoother player animations.** Opening and closing lyrics, credits, and history, and switching between the full and mini player, now drop far fewer frames, and closing a pane no longer flashes an empty background on its last frames.
- **A menu bar preview you can trust.** The preview at the top of `Settings → Menu Bar` is now built from the real menu bar item, not an approximation. It used to dim the artist whether or not that was on, show a title when nothing was playing, and never scroll. It now shows exactly what your menu bar will.
- **Menu bar controls at full strength.** They used to be drawn at the same dimmed weight as the player's glass buttons, which on the menu bar read as disabled. They now match every other menu bar icon.

## Fixed

- **A crash while the player resized on macOS 26.** Resizing the menu bar player could feed back into its own layout until the app ran out of stack. The player's size is now decided in one place.
- **Menu bar controls on macOS 27.** On macOS 27, clicking previous, play-pause, or next opened the player instead of pressing the button. They work again.
- **Play in Music starts playing.** On current versions of Music, the idle player's **Play in Music** button could do nothing even with your library open. It now starts playing reliably.
- **A crash when hovering the menu bar controls.** Moving the pointer over the previous / play-pause / next buttons could crash PlayStatus when their tooltip appeared.
- **Tooltips on the menu bar controls.** Every button used to show the same status line, and sliding from one button to the next lost the tooltip altogether. Each control now names what it does, and a greyed-out one says "Nothing playing".
- **Only one copy runs at a time.** Starting a second copy — from your Downloads folder next to the one in Applications, say — put two icons in the menu bar, polled your players twice, and recorded every song you played twice over. A second copy now quits and leaves the running one alone.
- **Tooltips inside the player.** The buttons in the player's header had no working tooltips, the Favorites tooltip was cut in half at the right edge, the volume row's tooltips hung off the bottom of the player, and tooltips in History were hidden behind the next row. Tooltips now always draw on top, flip above or below to stay on screen, and are never cut off.

---

# Also new in 3.1.1

Updating from 3.1.0? 3.1.1 finished the mini player's idle state.

- **The mini player offers a way to start playing** — the same one-tap "start playing" or "open the app" button the full player has.
- **Idle no longer keeps the last cover on screen.** It shows a plain plate instead of a blurred wash of whatever stopped playing.
- **The idle button and search agree on which player they mean.** With the source set to **Automatic**, a Spotify-only Mac is no longer offered Apple Music.

---

_Requires macOS 15 or later. Works with Apple Music and Spotify._
