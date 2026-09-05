<p align="center">
  <img src="docs/images/aetherplayer-logo.png" alt="AetherPlayer" width="160">
</p>

<h1 align="center">AetherPlayer</h1>

<p align="center">
  <b>A native media player built on <a href="https://github.com/superuser404notfound/AetherEngine">AetherEngine</a>, for macOS and iOS/iPadOS.</b><br>
  Drop or open a video or audio file, play it, switch audio and subtitle tracks, scrub with live thumbnail previews, and grab full-resolution frames.<br>
  macOS: universal binary (Apple Silicon + Intel), macOS 14.0+. iOS/iPadOS: universal app, iOS 17.0+.
</p>

<p align="center">
  <a href="https://github.com/superuser404notfound/AetherPlayer/releases/latest"><img src="https://img.shields.io/github/v/release/superuser404notfound/AetherPlayer?label=release&color=blue"></a>
  <a href="https://github.com/superuser404notfound/AetherPlayer/actions/workflows/release-dmg.yml"><img src="https://github.com/superuser404notfound/AetherPlayer/actions/workflows/release-dmg.yml/badge.svg"></a>
  <a href="https://testflight.apple.com/join/rgrjZ98V"><img src="https://img.shields.io/badge/iOS-TestFlight-0D96F6?logo=apple&logoColor=white"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple">
  <img src="https://img.shields.io/badge/iOS%2FiPadOS-17%2B-black?logo=apple">
  <img src="https://img.shields.io/badge/Swift-6.0%2B-F05138?logo=swift&logoColor=white">
  <img src="https://img.shields.io/badge/license-LGPL--3.0-lightgrey">
  <a href="https://discord.gg/P7NvpzNqnG"><img src="https://img.shields.io/badge/Discord-join-5865F2?logo=discord&logoColor=white"></a>
  <a href="https://ko-fi.com/superuser404"><img src="https://img.shields.io/badge/Ko--fi-Support-FF5E5B?logo=kofi&logoColor=white"></a>
</p>

---

## Install

**macOS:** grab the latest notarized `.dmg` from the [Releases page](https://github.com/superuser404notfound/AetherPlayer/releases), drag AetherPlayer to your Applications folder, and launch it. The `.dmg` keeps itself current through built-in auto-updates (Sparkle), so you only have to download it once. You can also try the beta on [TestFlight](https://testflight.apple.com/join/rgrjZ98V) (an App Store release is on the way).

**iOS/iPadOS:** join the public [TestFlight beta](https://testflight.apple.com/join/rgrjZ98V) (an App Store release is on the way), or build and run it from source (see [Build](#build) below).

## macOS features

- **Wide-format playback.** FFmpeg-backed decoding through AetherEngine, with an on-screen `native`/`sw` badge so you can see which rendering path a file took.
- **Audio too, with system Now Playing.** Open a music or audio file and AetherPlayer shows a dedicated Now Playing view (embedded cover art over a blurred backdrop, or a generated gradient when there is none). Playback wires into Control Center, the lock screen, and the keyboard media keys via `MPNowPlayingInfoCenter`.
- **Lip-sync correction.** J and K nudge the audio 50 ms earlier or later against the picture, for a soundbar or an AVR that adds video-processing latency. The value is shown on screen as you change it, and it is kept across sessions, because the error belongs to your audio chain and not to the file. Also in the Audio menu, with a reset.
- **Audio and subtitle track switching** from the menu bar or the tracks popover, with an "Off" option for subtitles. Drop an `.srt` onto a playing video to attach it as a sidecar track, and pick the subtitle size from the Window menu.
- **Disc titles and chapters.** Open a decrypted DVD-Video or Blu-ray `.iso` (from the Open dialog, a drop onto the window, or Finder's *Open With*) and the tracks popover lists its titles (pick one to switch) and the playing title's chapters (click to jump).
- **Scrub bar with live preview.** Hover the timeline for a thumbnail, click to seek, or drag to scrub.
- **Frame capture.** Save the current frame at full resolution (Cmd+Shift+S, or the camera button).
- **Recents with thumbnails.** Recently opened files show disk-cached keyframe thumbnails for quick visual recognition.
- **Resume where you left off.** Reopen a file and pick up at your last position.
- **Folder playlists.** Open a folder and step through its videos with Cmd+Left / Cmd+Right.
- **Tunable buffering.** Preferences (Cmd+,) set how far ahead to buffer, for slow or unstable network sources.
- **Dolby Vision composition (experimental).** No Mac reports a Dolby Vision display, so a Profile 8.1 source plays as its HDR10 base layer and the per-frame metadata is discarded. A Preferences switch hands the composition to AVPlayer instead. Off by default; on a display without the headroom for it, expect a shifted picture.
- **Stats for Nerds.** A live inspector window (Cmd+Shift+I) showing the active backend and decoder, resolution, frame rate, dynamic range, display mode, video and audio bitrate, channels, how the audio reaches the renderer, the lip-sync offset, A/V sync, dropped frames, and buffer state.
- **A silent file says why it is silent.** When a source carries audio that nothing in the chain can decode, playback used to continue silently with the reason only in the log. It now says so on screen, and the Stats inspector keeps the answer for the rest of the session.
- **Stays out of the way.** Controls auto-hide during video playback and reappear on mouse movement.
- **A diagnostics log you can hand over.** Every build writes the engine's diagnostics to a file; Help ▸ Reveal Diagnostics Log in Finder or Save Diagnostics Log picks it up. See [Reporting a playback problem](#reporting-a-playback-problem).

## Controls

| Action | Effect |
| --- | --- |
| Space / click | Play / pause |
| Double-click / F | Toggle fullscreen |
| Left / Right | Seek -/+ 10s |
| Cmd+Left / Cmd+Right | Previous / next in folder |
| Up / Down | Volume +/- 5% |
| M | Mute / unmute |
| J / K | Audio 50 ms earlier / later (lip-sync) |
| Escape | Exit fullscreen, else stop |
| Cmd+O | Open file |
| Cmd+Shift+O | Open folder |
| Cmd+Shift+S | Save current frame |
| Cmd+, | Preferences |
| Cmd+Shift+T | Toggle always on top |
| Cmd+Shift+I | Stats for Nerds |

The system media keys and Control Center transport also drive play / pause and track stepping, handy for audio.

## iOS/iPadOS features

A universal iPhone + iPad app (same source tree, sharing the playback core with the macOS app):

- **Open local files or a URL.** Pick a video or audio file from the Files app, or paste an `http`/`https` URL. While a remote open is in flight (a live tuner can take a few seconds to tune), Home shows an "Opening stream" pill with a cancel button.
- **Live streams (tuner / IPTV).** A "Live stream" toggle in Open URL loads straight on the engine's live path with a 30-minute DVR window, one tune-in, no size probing; URLs that resolved live once are remembered and open live automatically from then on. Sources that turn out live without the toggle are detected and reloaded. Live playback gets a live-aware transport bar: a behind-live offset instead of a duration, scrubbing across the DVR window, and a LIVE badge (red dot at the edge, gray while behind) that jumps back to the live edge. Teletext captions on live broadcasts render like any other subtitle track.
- **Custom playback chrome, matching the macOS design.** A transport bar with a scrubber (monospaced leading/trailing timecodes), a floating scrub-thumbnail preview while dragging, play/pause, and -/+10s skip. A top bar with Close, AirPlay, and Tracks. Controls tap to show/hide and auto-hide during playback, and a replay button appears when playback reaches the end.
- **Picture in Picture, AirPlay, and lock-screen Now Playing.** Playback is still hosted in an `AVPlayerViewController` under the hood, so PiP, AirPlay routing, and Control Center / lock-screen Now Playing come for free. Only AVKit's own visible chrome is hidden; its backend stays in place.
- **Track switching and lip-sync.** A tracks sheet lists audio and subtitle tracks, with an "Off" option for subtitles and support for attaching a sidecar `.srt`, plus a 50 ms audio-delay stepper for the latency Bluetooth headphones add.
- **Edge-swipe gestures.** A vertical swipe on the left edge adjusts brightness, on the right edge volume; the wide center stays a dead zone so a tap or a minimize swipe never nudges a level.
- **Recents.** Recently opened files show up on Home with cached thumbnails for quick re-open.
- **A diagnostics log you can hand over.** The button in the Home toolbar shares the same log the macOS app writes. See [Reporting a playback problem](#reporting-a-playback-problem).

## Reporting a playback problem

A file that will not play, freezes, stalls or picks the wrong decoder is almost always answerable
from the log, and almost never from a description. Every build (not just debug ones) writes the
engine's own diagnostics to a file:

- **macOS:** Help ▸ *Reveal Diagnostics Log in Finder*, or Help ▸ *Save Diagnostics Log…* to put a
  copy somewhere you can attach it from.
- **iOS/iPadOS:** the share button in the Home toolbar.

Open the file that misbehaves, let it fail, then export. The log opens with the app version, the OS,
the hardware and the display's HDR eligibility, and carries the load decisions, the served playlist
and any error code the player raised. It names the media files you opened, and no path around them.

Attach it to an issue at
[github.com/superuser404notfound/AetherPlayer/issues](https://github.com/superuser404notfound/AetherPlayer/issues).

## Build

Generated by XcodeGen:

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project AetherPlayer.xcodeproj -scheme AetherPlayer -destination 'platform=macOS' build
xcodebuild -project AetherPlayer.xcodeproj -scheme AetherPlayer-iOS -destination 'generic/platform=iOS' build
```

## Release build

```bash
DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="NOTARY_PROFILE" \
./Scripts/build-dmg.sh
```

Produces a notarized, stapled universal `.dmg`. Set `DEVELOPER_ID` for a signed local build; add `NOTARY_PROFILE` to notarize for distribution.

## Built with

Vibe-coded and maintained by [Vincent Herbst](https://github.com/superuser404notfound) in close pair-programming with **Claude** (Anthropic). The heavy lifting (demux, decode, HDR, audio) lives in [AetherEngine](https://github.com/superuser404notfound/AetherEngine); this repo is the macOS and iOS/iPadOS shell around it.

## License

[LGPL-3.0](LICENSE), matching AetherEngine. FFmpeg reaches the app through FFmpegBuild as dynamically linked frameworks under LGPL-2.1-or-later (no GPL components).
