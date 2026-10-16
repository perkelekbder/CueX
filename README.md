# CueX

CueX is a native macOS show-control app for Logic Pro playback projects.

## Current milestone

- Single-window macOS app with a compact vertical operator window that opens on launch
- Setlist fills most of the window, with large transport controls below and compact status in the footer
- Per-song note editors open from the row’s note button; file actions live in the setlist title menu
- Select a saved `.logicx` project
- Read `ProjectData` without modifying the Logic project
- Read Arrangement section names stored as plain text or RTF, while excluding the separate Marker-track sequence
- View section positions and stored durations as meter-aware bars and beats in song tooltips
- Edit per-section operator notes, stored in CueX's Application Support folder
- Reload the project after saving changes in Logic
- Send Play/Stop through Mackie Control and show Logic's actual playback state
- Locate selected sections through MMC, using the saved tempo map and frame rate
- Display live bars/beats from Logic and mark the current section independently of selection
- Show current-song progress in the footer; hover to see remaining bars/beats
- Step through selected songs with Previous Song / Next Song, locate them, and bring their notes into view
- Drag and drop songs in CueX, saving order on this Mac without modifying Logic
- Save a Stop After setting for each song; the final song is always locked on
- After an automatic stop is acknowledged by Logic, select and cue the next song ready for Play

The Logic project format is undocumented. The importer is isolated so its format assumptions can be revised without changing the app UI. It distinguishes the Arrangement sequence from the following Marker-track sequence using the observed sequence ordering. A local remote API and the iPhone browser view are future milestones.

## Connect Logic

Run CueX, then add a Mackie Control in Logic Pro → Control Surfaces → Setup → New → Install. Set Input Port to `CueX → Logic` and Output Port to `Logic → CueX`. For locating, also enable Listen to MIDI Machine Control (MMC) input in File → Project Settings → Synchronization → MIDI.

Position feedback uses the control surface's Beats clock mode. CueX offers Show Bars & Beats if Logic sends SMPTE instead. Only received feedback changes the current-section indicator; selecting a row locates it; use its note button to edit the operator note. The indicator uses bar/beat resolution, respects stored section lengths and gaps, and leaves beats that straddle a section boundary unmarked because Logic's division grid is configurable.

The footer’s song progress follows that same feedback, updating once per beat. Its progress percentage measures musical ticks within the section, and its remaining duration follows the saved meter changes. It freezes while Logic is stopped and clears outside song sections. It does not estimate elapsed or remaining seconds from tempo.

MMC locating currently assumes bar 1 is at 01:00:00:00 and supports saved 24, 25, or 30 fps non-drop projects. Locates round forward to the next frame; custom SMPTE offsets, fractional frame rates and drop-frame conversion need further work.

The Dock icon brings back the same operator window after closing or minimizing it. Closing the window keeps CueX running; use **CueX → Quit CueX** or **⌘Q** to quit, with the existing prompt for unsaved setlist changes.

## Keyboard controls

With the CueX operator window active, **Space** toggles Play/Stop and **↑ / ↓** select and locate the previous/next song in CueX order, without wrapping. Space also cancels a pending automatic restart. Holding a key triggers only one action per press. Shortcuts use the same behavior as the transport and song navigation buttons, including locating while playback is running.

Shortcuts are inactive while editing notes or another text field, while a dialog is open, or when another app has focus. Modified keys (such as Command/Shift/Option/Control combinations) keep their normal behavior.

## Save and recall setlists

Use the window’s Setlist menu or the File menu:

- **Save Setlist** (`⌘S`) saves the current order, operator notes, and Stop After settings to a `.cuex.json` file. Later saves update that file.
- **Save Setlist As** (`⇧⌘S`) creates another named version, so multiple setlists can use the same Logic project.
- **Open Setlist** (`⌘O`) restores a saved version while playback is stopped.
- **Open Recent** in the File and Setlist menus remembers the last ten successfully opened or saved setlists across launches. Most recent comes first. Clear Menu removes this history without deleting files. Missing files show an error and can be located with Open Setlist.

The heading shows the file name and a dot for unsaved changes. Edits still save to the local working copy automatically; use Save to update the portable file. CueX prompts to save unsaved changes before switching projects/setlists or quitting.

To transfer a setlist, copy its file and the `.logicx` project, including audio, to the other Mac. CueX first looks for a matching project beside the setlist, then at its original location, and otherwise asks you to locate it. Save after relinking to remember the new path. The setlist does not contain audio, tempo data, or a copy of the Logic project. CueX reads those from the linked saved project and never writes to it.

Song matching uses imported section names and start positions. If sections were renamed, moved, added, or removed in Logic, CueX rejects the old setlist rather than silently attaching settings to different songs; import the updated Logic project to make a new setlist. The final song’s Stop After lock is always enforced on recall.

## Arrange the CueX setlist

Drag a song row to its new position while playback is stopped. Reordering preserves the selected song and does not change Logic’s arrangement. Previous Song / Next Song follow the CueX order. The order is restored on reload; newly imported sections are appended and removed sections are dropped. Notes and stop settings stay attached to their songs. The locked final stop follows the last row in CueX.

Unchecked songs continue naturally when the next setlist song starts exactly at the current song’s end in Logic. Otherwise CueX stops at the boundary, waits for stopped feedback, locates the next song, and resumes only after fresh position feedback confirms that song. These jumps can introduce a brief gap; they are not gapless transitions. A failed locate or a missing position confirmation leaves playback stopped. CueX’s Stop button cancels a pending automatic restart.

## Song and setlist duration

Each song row shows its duration in minutes and seconds. The footer shows **Setlist length**, the sum of the songs in CueX. Durations integrate the saved tempo changes across each song’s start and end ticks. They refresh when the project is imported or reloaded after a Logic save.

The total excludes gaps in Logic’s timeline, time waiting at programmed stops, and the brief delays of MIDI-controlled jumps. Songs are summed before rounding the total to the nearest second; row durations are also rounded to the nearest second. Durations longer than an hour continue counting minutes, for example `75:30`. If a song has no usable tempo map, its duration and the total show `—` instead of assuming a tempo or showing a partial total.

## Detect saves in Logic

CueX monitors the linked project’s saved `ProjectData` and frame-rate metadata, including when a setlist was opened from a file. It polls every half second and waits for a stable snapshot before reloading. Display-state updates and backup files do not trigger reloads.

After Logic saves, a warning appears in the footer before CueX reloads the project. During playback or an automatic transition, the warning stays visible and reloading waits until playback stops. Starting playback is disabled while a reload is pending; Stop remains available. After reloading, click the footer notice to dismiss it. If the project is temporarily unavailable or cannot be read, CueX keeps the previous imported state and offers retry from the footer.

Reloading preserves CueX order, notes, stop settings, and selection for matching songs. Exact section matches are kept first; moved songs can match by unique name, and renamed songs by an unambiguous start position. Unmatched new songs are appended in Logic timeline order, and removed songs leave the list. Orphaned notes and stop settings remain in the local working copy. Ambiguous edits cannot be matched automatically. Reloading does not send a locate or start playback. Save the setlist file again to keep changes to its song list.

## Stop and return to the setlist start

The first Stop pauses playback at its current position. Pressing Stop again, or pressing it while already stopped, cues the first song in CueX’s current order and keeps playback stopped. Two quick clicks also work if Logic hasn’t acknowledged the first Stop yet.

CueX also watches Logic’s musical-position feedback: if Logic jumps back to its exact project start while stopped (for example, after Stop is pressed again in Logic), CueX redirects it to the first setlist song. Deliberately selecting a CueX song that starts at Bar 1 remains valid. Logic doesn’t identify why its playhead moved, so a manual jump to the exact project start while stopped is handled the same way. This requires working position feedback and MMC locating.

## Program automatic stops

Use the Stop After checkbox on each setlist row to program the playlist. Unchecked songs continue into the next song. Checked songs stop at their end, then CueX waits for Logic to confirm that playback stopped before locating the next song and selecting its row. The last song's checkbox is always checked and locked; it stops without wrapping to the first song. Settings are stored on this Mac alongside the project's operator notes.

Automatic stops require CueX to remain running with working MIDI input/output and Logic's MMC input enabled. They use the saved tempo map and within-beat clock feedback, with a 30 ms delivery lead before the section boundary. They are software-timed, not an audio mute or a native Logic project end marker. If position feedback is lost for 750 ms during playback, or boundary timing is unavailable, CueX sends Stop and does not automatically cue another song. A missing stop acknowledgement also prevents automatic cueing. Save timeline and tempo changes in Logic, then reload CueX before using the programmed stops.

## Build and run

Requires macOS 14 or newer and Xcode 16 or newer (Swift 6). Open Xcode once to finish installation and accept its terms. The repository contains a Swift package with no external package dependencies. Open `Package.swift` in Xcode, or work from Terminal in the repository folder.

To create a Finder-launchable app and ZIP archive:

```sh
./scripts/build-app.sh
```

The script uses the full Xcode toolchain. If the active tools point to standalone Command Line Tools, it uses `/Applications/Xcode.app` when installed, without changing system settings. For Xcode installed elsewhere, set `DEVELOPER_DIR` to its `Contents/Developer` directory before running the script.

The script prints the app and archive paths under `Builds/CueX-<timestamp>/`. Quit any older CueX process before launching the new app, so only one copy creates the MIDI ports. Each build targets the Mac architecture it was built on; this script does not create a universal binary.

For development:

```sh
swift run
```

Run the existing protocol and meter-map checks with `swift test`.

## Share with friends

Share the Git repository with friends who want to build or change CueX. Friends who only want to run the app can use the generated `CueX.zip` without installing Xcode. They will need macOS 14 or newer, a compatible Mac architecture, Logic Pro, and the MIDI setup described above. These local builds are ad-hoc signed, not notarized; macOS may require approval when opening a downloaded copy.

Generated builds, SwiftPM caches, personal `.logicx` projects, `.cuex.json` setlists, and macOS metadata are excluded from Git. Keep music and personal show settings separately. App archives can be attached to a hosted repository’s releases.

A source-code license has not been selected yet.
