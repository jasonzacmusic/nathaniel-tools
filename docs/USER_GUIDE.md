# Nathaniel Tools — the user guide (plain English)

*Written for a musician, not a programmer. If a word here needs a dictionary, that is a bug — tell us.*

Nathaniel Tools is a small set of REAPER add-ons Jason Zac built for his own multitrack sessions.
Everything installs from inside REAPER, is free, and is open source (MIT).

---

## 1. Install (once, two minutes)

1. Make sure REAPER has **ReaPack** and **ReaImGui** (both free). If not: download from
   `reapack.com` and `github.com/cfillion/reaimgui/releases`, drop the file into
   REAPER's `UserPlugins` folder, restart REAPER.
2. In REAPER: **Extensions → ReaPack → Import repositories…** and paste

   ```
   https://raw.githubusercontent.com/jasonzacmusic/nathaniel-tools/main/index.xml
   ```

3. **Extensions → ReaPack → Browse packages…**, right-click **Nathaniel Tools** → **Install All**.
   (Install All matters: the apps share one "Shared Libraries" package.)
4. Updates: **Extensions → ReaPack → Synchronize packages** whenever you like.

After that everything is in **Actions → Show action list**, filter on the app name.
Add a key to anything: select it → **Add…** → press the key (or the MIDI pedal).

---

## 2. What each app is for

Colour is the language: **green = structure · amber = delivery · violet = performance · teal = look.**

### Palette & Look — teal
Colours and names your tracks from what they *are*. It reads the track name, its folder,
and the plugins on it, works out "this is a bass", "this is a bus", "this is a reverb
return", and paints it the colour you chose for that family. Your own rules ("anything
called *harm* → purple") sit on top and win. It can also colour markers/regions the same
way, name tracks after their audio file, number them, and re-colour on the fly (LIVE)
as you add tracks.

**Use it when:** a session has grown past twenty tracks and you can't find the guitars at
a glance. Press **APPLY COLOURS**. Done. Files someone gave you? **Rename + one colour**
(the old Y key): names from the items, one colour for the lot, **Try another colour** until it
looks right; **Number them → same for all** puts one batch number in front of every name.

### Folders & Flow — green
Folders without dragging. Tick tracks → **Make folder**. Indent, outdent, pull a track out,
dissolve a folder, move a whole folder up or down, hide everything except one folder while
you work on it, and **Repair folder maths** for the session where one folder never closed
and swallowed everything after it.

**Use it when:** you are building or fixing the shape of a session.

### Track Settings Transfer — green
Pro-Tools' "Import Session Data", for REAPER. Open two project tabs, pick FROM and TO;
it matches tracks by name and copies FX chains, volume, pan and sends onto the matching
tracks — or builds the missing ones. Green rows are exact matches. Amber rows are guesses
and are *unticked* until you say yes. Nothing is written until you press TRANSFER and
confirm. Automation is never copied.

**Use it when:** last week's session has the vocal chain you want in this week's.

### Stem Print & Handoff — amber
Prints stems and puts your session back exactly as it was. Tick tracks and buses,
choose **Raw** (no plugins, your fader and pan as they are), **To the bus** (plugins
on, fader + pan, every send muted — no reverb or delay), **Through master** (each
stem alone through the master bus and its plugins — your "Stems Default" preset) or
**Fully wet** (each stem solo-in-place *with* its reverbs and delays). Tick
**Unity fader, centre pan** only when a mixer wants clean files.
Tick **Build a handoff tab** and you get a new project tab with the same names,
colours and folders, no plugins, and each printed file already on its track — that tab
is what you send. Also: **Uppercase bus names**, **Plugin-free clone tab**.

**Use it when:** something leaves your room — to a mixer, a collaborator, another DAW.

### MIDI Batch Export — amber
Many `.mid` files in one go. Choose the source (selected items / items on selected
tracks / regions / every MIDI item), a name pattern (`$num - $name`), a folder, see the
exact filenames it will write, press EXPORT. It refuses to overwrite by accident.

**Use it when:** you want every riff/idea from a session as its own MIDI file.

### StageRig — violet (early version)
Live patch switching for the stage. **StageRig Build** turns a setlist into a project
(one folder per patch, instruments loaded); **StageRig** shows NOW and NEXT in big
letters and switches without cutting off the chord you are still holding (the outgoing
patch rings out, then is flushed and muted). GO / PANIC / ALL OFF. Space or Enter = GO.
Bind **StageRig Next** and **StageRig Panic** to footswitches for hands-free.

**Honest status:** it works, it has not yet played a paid show. Keep a backup rig
until it has.

### The speed layer — 12 one-key actions
Each replaced a REAPER custom action that was quietly doing the wrong thing.

| Key (Jason's layout) | Action | What it does |
|---|---|---|
| **A** | Solo Focus | Solo just what's selected (in place); press again to clear all solos |
| **⇧A** / pedal CC75 | Record Arm Toggle | Arm only the selected tracks; press again to disarm all |
| **NumPad 6** | FX Float Toggle | Float the first plugin on the selected track / close it |
| **⇧F** / pedal CC76 | FX Open/Close All | Open every plugin window on the track, or close them all |
| **N** / **B** | Region Next / Prev | Jump to the next/previous region (playback follows on the bar) |
| **M** / pedal CC23 | Marker at Bar | Drop a marker exactly on the nearest bar line |
| **⌘⇧T** | Tempo at Bar | Insert/edit a tempo or time signature exactly on a bar |
| **⇧⌃M** | MIDI Render | Export the project MIDI for the time selection with one key |
| **⌘⌃V** | Flush Paste | Empty the selected tracks and paste the clipboard in their place, save silently |
| **⇧D** | Duplicate Track | Duplicate the track empty and armed — the next layer, instantly |
| **E** | Unsolo & Unselect | The reset key: clears solos, arms, selections, time selection |
| *(pedal)* | Toggle Chorale | Finds the Chorale plugin wherever it is and flips it on/off |
| **Control+click** in the bottom half of an item | Stretch Marker at Mouse | Adds a stretch marker right under the pointer (assigned as a mouse modifier) |
| **F** | Instant Folder | A NEW folder track appears above the selected tracks, named from what they share (ELECTRIC, KICK), coloured like them, a little taller; nothing else moves |
| **⌥G** | Edit Group from Selection | The selected tracks edit together (split/trim/move) but faders, mutes, solos stay independent; press again to ungroup. Clutch = ⌘⇧G (toggle all grouping) |
| **Z** / **X** | Trim Left / Right No Overlap | Trim the item edge to the cursor AND keep the neighbour from overlapping — items butt, no tangled crossfades |
| — | Unoverlap Items | Fix existing overlaps on selected items / tracks: the earlier item is cut where the next one starts |

Keys are *suggestions* — bind whatever you like in the Actions list.

---

## 3. Every window works the same way

* **They open in the docker** — "Open Dock" (also run at REAPER start on Jason's Mac) puts
  Palette & Look, Folders & Flow, Track Settings Transfer, Stem Print and MIDI Batch Export
  in the docker as tabs. Untick **Dock** to float one; it remembers.

* **Header** — the app name, what it does in five words, and **Dock** (put it in
  REAPER's docker next to the mixer).
* **Sections** in capitals tell you the order: what → where → which tracks → the big
  button.
* **One big button** does the thing. Anything that changes your session in a big way
  asks first.
* **The status line at the bottom** always tells you what just happened. **Log** opens
  the history. Nothing happens silently.
* **Tick columns paint** — press on one box and drag down to tick many.
* Hover anything for a tip in plain words.
* Every action is one **Undo** step, named in plain words.

---

## 4. If something is wrong

* An app says it needs the "Shared Libraries" package → ReaPack → Browse → Nathaniel
  Tools → Shared Libraries → Install (or Install All on the repository).
* A window opens but shows an error line at the bottom → the window stays up; read the
  line, and send it to us. Nothing was written to your session.
* **Actions → Show action list → Nathaniel Tools: Shared Libraries** prints what is
  installed and what version.

Support: WhatsApp **+91 7760456847** · issues on GitHub · `music@nathanielschool.com`.
