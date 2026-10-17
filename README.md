# CueX

CueX is a native macOS show-control app for Logic Pro playback projects.

## Current milestone

- Single-window macOS app with a compact vertical operator window that opens on launch
- Logic-inspired charcoal/gray surfaces, white labels, blue controls, and colored status indicators
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
- Show live progress inside the selected song row; hover to see remaining bars/beats
- Step through selected songs with Previous Song / Next Song, locate them, and bring their notes into view
- Drag and drop songs and custom pause/full-stop blocks in CueX, saving order on this Mac without modifying Logic
- Save a Stop After setting for each song; a permanent, movable Full Stop block ends the set
- After an automatic stop is acknowledged by Logic, select and cue the next song ready for Play

The Logic project format is undocumented. The importer is isolated so its format assumptions can be revised without changing the app UI. It distinguishes the Arrangement sequence from the following Marker-track sequence using the observed sequence ordering. A local remote API and the iPhone browser view are future milestones.

## Connect Logic

These steps let CueX press Play and Stop in Logic and move to the beginning of a song.
Keep both apps open while you use CueX.

### 1. Open your project

1. Open **Logic Pro** and the project you want to play.
2. Save the project: hold the **Command (⌘)** key and press **S**.
3. Open **CueX** and leave it running so Logic can find its connection names.

### 2. Tell Logic to listen to CueX

1. Click **Logic Pro** in the menu bar at the very top of your screen.
2. Choose **Control Surfaces**, then **Setup**.
3. In the window that opens, choose **New → Install**.
4. Find **Mackie Control** and add it; this is the name of the connection type, and you do not need to own a Mackie controller.
5. Select the Mackie Control you added so you can see its settings.
6. Click the **Input Port** menu and choose **CueX → Logic**; this sends your button presses from CueX to Logic.
7. Click the **Output Port** menu and choose **Logic → CueX**; this lets Logic tell CueX what is playing.

If the CueX names are missing, make sure CueX is still open, then close and reopen this setup window.

### 3. Allow CueX to jump to songs

1. Go back to Logic's main project window.
2. At the top of the screen, choose **File → Project Settings → Synchronization**.
3. Open the **MIDI** tab.
4. Tick **Listen to MIDI Machine Control (MMC) input**; this allows CueX to move Logic's play position.
5. Save the project again with **⌘S**.

### 4. Open the same project in CueX

1. In CueX, click the setlist title at the top of the window.
2. Choose **Select Logic Project…**, find the project you just saved, and open it.
3. CueX takes song names from Logic's **Arrangement sections**, the named sections above the tracks; ordinary Logic markers are not used.
4. If CueX shows **Show Bars & Beats**, click it so Logic reports positions as bars and beats.
5. Select a song in CueX and press **Play**; Logic should move to that song and begin playing.
6. Press **Stop** to stop playback.

If Logic does not move to the selected song, go back to step 3 and check that **Listen to MIDI Machine Control (MMC) input** is ticked.

## Project compatibility

Song jumping currently expects bar 1 at timecode `01:00:00:00` and a saved frame rate of 24, 25, or 30 fps without drop-frame timecode.
Other timecode start positions and frame rates are not yet supported; beyond bar 999, cue a song from CueX to anchor the full bar number, because Logic’s three-digit Mackie display cannot identify large manual jumps between thousand-bar ranges.

## Connection health

The light at the bottom shows green for recent communication, amber while waiting or when Logic has been quiet, red for a connection problem, and gray when Logic is closed.
Click it for details and connection instructions.

## Keyboard controls

The **Playback** menu provides Reset (**Enter**, sends Stop twice), Stop (**0**), Start/Stop (**Space**, depending on playback state), Toggle Cycle (**C**), Previous (**,** or **↑**), and Next (**.** or **↓**).
Shortcuts work in the CueX window, leave text editing, dialogs, and other apps alone, and let Space cancel a pause countdown or pending automatic restart.

## Cycle

Click **Toggle Cycle** between Previous and Next to turn Logic’s existing cycle range on or off.
The button turns amber when Logic confirms Cycle is on and gray when off, including changes made in Logic; hover to check whether the state is still unknown while waiting for feedback.

## Copy setlist

Choose **Edit → Copy** or press **⌘C** to copy plain text with one song name per line and `----` for each pause, excluding Full Stop and everything after it.
No other information is copied, and text fields keep normal text copying while you edit.

## Save and recall setlists

Use **Save Setlist (⌘S)** to save song order, pauses, Full Stop position, notes, and Stop settings to a `.cuex.json` file, or **Save Setlist As (⇧⌘S)** to keep another version.
Use **Open Setlist (⌘O)** or **Open Recent** to recall one; a dot beside the title means the portable file has unsaved changes, even though CueX keeps a local working copy automatically.

## Transfer a setlist

Copy the `.cuex.json` file and its Logic project, including audio, to the other Mac, preferably into the same folder.
Open the setlist in CueX, locate the matching Logic project if asked, and save again to remember its new location.

## Arrange the CueX setlist

While stopped, drag songs or blocks into the order you want without moving anything in Logic.
The selected row and its progress follow Logic’s playhead, and playback follows CueX order with a possible brief gap when jumping between songs.

## Song notes

Click a song's note button to write or edit a reminder.
Notes stay attached to their songs when you reorder and are included when you save the setlist.

## Pause blocks

Use **+ → Add Pause**, drag the pause into place, and click its seconds value to choose how long Logic waits before automatically starting the next song, even if the preceding song's Stop box is checked.
Right-click a pause to remove it; **Stop** cancels a running countdown, and **Play** restarts that pause from its full length.

## Full Stop

Every setlist has one permanent **Full Stop**, initially at the end, which you can drag earlier to shorten the set and save in that position.
Its Stop box stays locked on, and everything below it is grayed out, blocked from playback through CueX, and excluded from set timing.

## Song and setlist duration

Song rows show their lengths and the selected song's progress bar, while the large numbers at the top show remaining time and estimated finish using Logic's saved tempo changes and including scheduled pauses up to Full Stop.
Durations use `MM:SS` or `HH:MM:SS` for an hour or more, while the finish clock omits seconds and assumes no extra manual waits or transition delays.

## Detect saves in Logic

When you save the project in Logic, CueX shows a notice and reloads it once playback and automatic transitions have stopped, preserving matching songs' order, notes, settings, and custom blocks.
Save the CueX setlist again to keep the updated song list in its portable file.

## Stop and return to the setlist start

**Stop** pauses a playing song; press it again, or press it while already stopped, to return to the first setlist row without starting playback.
If Logic jumps to bar 1 while stopped, CueX also redirects it to the setlist start, except when you deliberately selected a song that begins at bar 1.

## Program automatic stops

Check a song's **Stop** box to stop at its end and prepare the next song for you to press Play; leave it unchecked to continue automatically.
Full Stop always ends the set, and automatic control requires CueX to remain open with the Logic connection working.

## Build and run

Building from source requires macOS 14 or newer and Xcode 16 or newer, opened once to finish setup.
Run `./scripts/build-app.sh` from the project folder to create the app and ZIP under `Builds/`, then quit any older CueX before opening the new app.

## Share with friends

Share the generated `CueX.zip` with friends who have a compatible Mac and Logic Pro, or share this repository if they want to build the app themselves.
Keep Logic projects, audio, and saved setlists separately; macOS may ask for permission to open a downloaded app.

## License

CueX is licensed under the [MIT License](LICENSE).
Commercial reuse is welcome; copies or substantial portions of the software must retain the license and copyright notice crediting Yevhenii Zhytniuk and CueX.
