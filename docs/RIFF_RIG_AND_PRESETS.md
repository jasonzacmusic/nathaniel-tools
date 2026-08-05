# StageRig — your live rig in REAPER

Built 5 Aug 2026. Everything below uses plugins and presets that are actually on your Mac —
I read them off `JZPianoRiffSet.RTrackTemplate`, the Arturia factory folder, and the ANA 2
preset library. Nothing here is invented.

---

## 1. The patches

You use **Pianoteq 8**, not 9 — your own template says so, so the rig matches it. Your house
EQ (**Eiosis AirEQ Premium**, preset "Jason Default EQ setup") goes on every patch, same as
your template.

| # | Patch | Plugin | Loaded preset | Your other three |
|---|---|---|---|---|
| 1 | GRAND | Pianoteq 8 | Bösendorfer 280VC | NY Steinway D Wide Unison · Steingraeber Prepared · Erard Recording |
| 2 | UPRIGHT | Pianoteq 8 | K2 Basic | J. Broadwood Felt · K2 Felt I · Erard Recording |
| 3 | RHODES | Pianoteq 8 | MKI Leslie | Electra RubberChorus · MKI Basic · MKII Basic Stereo |
| 4 | WURLI/CP | Pianoteq 8 | W1 Basic Stereo | CP-80 Amped · Pianet T Concrete · Electra RubberChorus |
| 5 | CLAV | Pianoteq 8 | Clavinet D6 Growl | Clavinet D6 Comp · D6 Basic · D6 Auto-Wah |
| 6 | ORGAN | Arturia B-3 V2 | Clean Jazz | Mr. Jimmy Smith · Full Drawbars · Church Chords |
| 7 | LEAD | ANA 2 | A Beautiful Dread Lead | Astro Guitar Lead · Bodzin Lead · A Leadle Square |
| 8 | PAD | ANA 2 | Big Mellow Pad | 9 Choirs Pad · Big Choir · Blister Pad |
| 9 | BANJO | ANA 2 | **Banjo** | Dystopian Banjo |
| 10 | ETHNIC | ANA 2 | Kalimba | Dreamy Kalimba · Honky Tonk Kalimba · Angel Harp |

**You were right about the banjo.** It's in ANA 2 — the *Slate Digital Ultra Multisample 2*
expansion, presets `Banjo` and `Dystopian Banjo`. I'd first looked for a dedicated banjo
plugin and found none; your correction was the right one.

Every patch track carries its alternate presets **in the track's own notes**, so on stage
they're in front of you instead of in a document.

> **One honest caveat.** REAPER can only select a preset the plugin exposes to the host.
> Pianoteq and ANA usually do; Arturia sometimes doesn't. Where it doesn't take, the plugin
> still loads correctly and you pick the preset once by hand — then
> *File → Project templates → Save project as template* and it's permanent.

---

## 2. How switching actually works — and why it doesn't glitch

Every instrument is loaded **when the project opens** and never touched again. Switching
does **not** load, unload, bypass or reconfigure anything.

In front of each instrument sits a tiny plugin I wrote for this — **NPH Patch Gate**. It
decides whether new notes reach the instrument behind it.

Switching from A to B:

1. **Open B's gate** — B can now make sound
2. **Close A's gate** — A takes no *new* notes
3. **A rings out naturally** — because the gate blocks note-ons but **never** note-offs
4. On closing, A releases everything it was holding plus sustain (CC64 = 0)

So a held chord decays like a real instrument instead of being chopped off, and nothing can
drone into the next song. There is no audio glitch because no audio processing is ever
created or destroyed.

**A combo patch is just two gates open at once.** There's no separate code path for layers
— which is exactly why they're instant and can't break. `BANJO + ETHNIC`, `GRAND + PAD` and
`RHODES + LEAD` are set up already; add your own by editing the `COMBOS` table at the top of
the build script.

---

## 3. Chorale on the footswitch

The VOCAL track has **Chorale** loaded and **bypassed**. It starts off deliberately — you
don't want to discover you've been singing through a harmoniser all through the verse.

In the StageRig panel, click **learn** next to CHORALE, press the pedal, done. The mapping is
stored **in the project**, so each concert carries its own footswitch layout and you're never
one wrong preset away from silence.

Same for **PANIC** — closes every gate and sends all-notes-off on all 16 channels.

---

## 4. Triggering loops — the honest answer

REAPER is **not** Ableton, and anyone who tells you a script makes it Ableton is selling
something. Here's what's genuinely true, in order of how well each works live.

### A. Section launching — solid, native, this is the one to use

REAPER has a feature Ableton people don't expect: **smooth seek**. With
*Options → Smooth seek (seeks position when reaching end of measure)* turned on, any jump you
trigger **waits for the end of the bar** and then happens in perfect time.

Combine that with regions and you have real quantised scene launching:

- Lay each section out as a **region** — Verse, Chorus, Solo, Outro
- Bind `Region: Go to region 01…` etc. to footswitches
- Hit the pedal mid-bar; nothing happens until the bar ends, then it jumps in time

You already own the hard part: your Riffs sessions are **full of regions** (R1–R7 in the
session open right now). This is REAPER doing what it's genuinely good at, and it needs no
scripting at all.

**Limit, stated plainly:** this moves the *whole playhead*. Every track jumps together. It's
scene launching, not per-track clip launching.

### B. Per-track loop pads — for independent loops

For loops that fire independently of the timeline, use **ReaSamplOmatic5000** — one instance,
one loop per MIDI note. The template builds a `LOOP PADS` track with RS5k ready.

- Drop a loop onto RS5k, set its note
- Foot pad sends that note → loop fires
- Set RS5k to *Loop* and it repeats until you release or retrigger

**Limit, stated plainly:** RS5k fires the sample the instant the note arrives — it does
**not** wait for the bar line. For a loop that must lock to the grid, either play the pad in
time yourself, or use approach A.

### C. What REAPER genuinely cannot do

There's no native, sample-accurate, per-track, bar-quantised clip launcher with follow
actions. That's Ableton's Session View and it's the one thing REAPER has no real answer for.
Scripts that claim otherwise are polling at UI rate (~15–30 ms) and will drift.

**My recommendation:** use **A** for song structure — it's rock solid, native, and matches how
you already work with regions. Use **B** for one-shots, stabs and pads you trigger by feel.
Don't try to rebuild Session View; you'd be fighting the tool.

---

## 5. Your foot controllers

All three work the same way — anything that sends MIDI.

- **Keith McMillan 12 Step** — sends *notes*. Great for patches: twelve patches, twelve steps.
- **SoftStep / other KMI** — sends notes or CC, fully programmable.
- **Plain MIDI pedals** — usually CC (sustain is CC64).

StageRig learns either. Click **learn**, press the pedal, it stores what it saw
(`note:60` or `cc:80`) against that slot **in the project**.

**Suggested layout for the 12 Step:**

| Step | Does |
|---|---|
| 1–5 | GRAND · RHODES · CLAV · ORGAN · PAD |
| 6 | BANJO |
| 7 | BANJO + ETHNIC combo |
| 8 | LEAD |
| 9–10 | Region: previous / next section (see §4A) |
| 11 | CHORALE on/off |
| 12 | PANIC |

---

## 6. Running it

1. **Actions → Show action list → New action… → Load ReaScript** →
   `NPH/NPH_StageRig Build Template.lua`, then Run.
   It builds the whole rig **in a new project tab** — your open session is never touched.
2. Load `NPH/NPH_StageRig.lua` the same way. That's the live panel. Dock it.
3. Fix any presets the host couldn't select, then
   **File → Project templates → Save project as template**.

> **Wispr Flow.** While I was working, Wispr Flow injected keystrokes into REAPER and opened
> a *Dynamic split items* dialog on your live Riffs session. I cancelled it and nothing was
> applied. **Quit Wispr Flow before running these**, or before any session where a stray
> keystroke would be expensive. It's a documented hazard in the tech brief and it's real.

---

## 7. What I'd add next

- **Setlist mode** — order the patches per song, one pedal for "next", so a whole gig is one
  forward button. The data model already supports it; it's UI work.
- **Note tracker with re-strike** — currently a switch releases held notes. It could
  optionally *re-strike* them on the incoming patch so a sustained chord changes timbre
  without you replaying it. That's the MainStage trick worth stealing.
- **Stage view** — a full-screen CURRENT/NEXT display with a BPM flasher, for when the laptop
  is on the floor and you're reading it at a glance.
