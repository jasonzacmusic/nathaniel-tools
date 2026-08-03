# StageRig Research: REAPER as a Live Keyboard Rig + Trustworthy Loop Triggering
**Research date: 2026-08-03.** All prices/versions as found on the cited pages at research time.

---

## 1. Existing REAPER live-performance solutions

### 1.1 SWS LiveConfigs — the canonical "REAPER as patch switcher" tool

LiveConfigs ("Live Configs") ships inside the free SWS/S&M extension. It was written by "Jeffos" (S&M), explicitly "made for live performers by live performers." Primary documentation is a PDF last revised **February 2012** and written against **REAPER v3.73** — which tells you how long this space has been frozen. Source: [S&M Live Configs Ed.2 PDF](https://sws-extension.org/download/S%26M_LiveConfigs_Ed2.pdf).

**How it works (from the official PDF):**
- A "config" is a table of rows; each row maps a **MIDI CC data value** (0–127) to: a target track, an optional track template file, an optional FX chain file, optional FX user presets (.rpl), and optional activate/deactivate actions (native Command IDs or SWS Custom IDs).
- Typical setup: one armed "input track" routes MIDI/audio to a bank of patch tracks; **all config tracks are muted except the active one**. Switching = unmute new + mute old. "Immediate and seamless switching between configs (no disk access during switches: everything is already present in the project file)."
- Up to **8 configs** can run simultaneously (e.g., one per band member on the same machine).
- Options per config: *Enable*, *Mute all but active track*, *Auto track selection*, *Input track* selection.
- Only the **last "stable" MIDI message** is processed (a `CC_DELAY` setting in S&M.ini, default nonzero — deliberate debounce so sweeping a knob doesn't fire every intermediate config). Note-On can be used via "Live Config #n – Next/Previous" actions.

**Official recommended live settings (verbatim from the PDF, still the best checklist for any REAPER live rig):**
- Preferences > Audio > "Close audio device when inactive": **all disabled** ("we want the audio engine whatever happens")
- Preferences > Audio > Buffering > **Allow live FX multiprocessing** enabled + correct CPU count
- Preferences > Audio > Playback > **Run FX when stopped** enabled
- Preferences > Audio > **Track mute fade: 100 ms** (LiveConfigs obeys this → glitch-free switches)
- Preferences > Audio > **Do not process muted tracks: enabled** (CPU savings when "mute all but active track" is on)
- General > **Maximum undo memory: 0** (undo disabled)
- Launch a dedicated live profile: `reaper -cfgfile ReaperLive.ini myLiveConfigs.rpp`

**Documented limitations:**
- CC-absolute-only control: most keyboards send **Program Change**, not CC, so users need a PC→CC translator JSFX ([example workaround write-up](https://blog.lzc256.com/posts/reaper-translate-pc-to-cc-to-allow-the-use-of-sws-liveconfig/)).
- The "FX user presets" column is **"not yet available on OSX"** (per the PDF; macOS support has lagged in this tool historically).
- Track-template/FX-chain switching modes cause disk access + plugin instantiation delays ("longer switches... might be interesting for large sample-based effects though") — i.e., the fast path requires *everything preloaded in RAM*.
- One config row = one track. Users have requested one config → multiple tracks for years: [sws issue #888](https://github.com/reaper-oss/sws/issues/888), [sws issue #689](https://github.com/reaper-oss/sws/issues/689).
- The PDF's own reliability advice: *"I must have a backup solution ready to go — even if totally degraded!"*

### 1.2 ReaScript setlist/patch switchers

- **cfillion's "Song Switcher"** (in ReaTeam ReaScripts, actively maintained): each song is a top-level folder track named `# Song Name`; switching **mutes and hides** every song except the current one; optional stop/seek on switch; take markers starting with `!` fire as action markers; ships a **web-browser remote** (`song_switcher.html`) for tablet control. Works best with "Do not process muted tracks" + "Track mute fade" enabled — same muting architecture as LiveConfigs. Sources: [forum thread "ReaScript: Song switcher for live use"](https://forum.cockos.com/showthread.php?t=181159), [script source on GitHub](https://github.com/ReaTeam/ReaScripts/blob/master/Various/cfillion_Song%20switcher.lua).
- **ExtremRaym's "Interactive Music Scenes Switcher"** ReaScript pack ([extremraym.com](https://www.extremraym.com/en/download/reascripts-pack-interactive-music-scenes-switcher/)).
- **LBX Stripper** — snapshot/channel-strip control surface for REAPER, where the "REAPER Live Pedalboard Project" community migrated after outgrowing LiveConfigs.
- **Floopa Station** — paid Gumroad ReaScript: 5-track live-looping "station" with auto-loop alignment, custom MIDI mapping, count-in, beat counter ([Gumroad](https://floopreaperscript.gumroad.com/l/tiqprz)).
- S&M "Project loader/selecter" actions for sequentially loading song projects ([forum post](http://forum.cockos.com/showpost.php?p=831103&postcount=655), linked from the LiveConfigs PDF).

### 1.3 What gigging users actually report

- [The REAPER Blog: "REAPER as live VST host with SWS Live Configs" (2014)](https://reaper.blog/2014/07/reaper-as-live-vst-host-with-sws-live-configs/) — a keyboardist (Sven) runs synths+FX with snapshots + LiveConfigs, praises REAPER's "stability and efficiency... very low latency."
- [KVR tutorial thread on the same rig](https://www.kvraudio.com/forum/viewtopic.php?t=410429) — praised: surprisingly low latency, stability, low memory footprint, fast startup. Complaints: **"when you start off, it's not that simple"** (multi-day setup: tracks, KX MIDI Filter for splits/zones, floating VST window positions per song, MIDI-learn on configs); **tempo can't change per song via snapshots** ("tempo is defined for the whole file"); SWS snapshots don't remember floating/docked FX window states; "Reaper is a bit slow to build up the VST GUIs" when switching. Notably the author *also* ran Cantabile 3 on stage — REAPER didn't fully replace a dedicated host even for its advocate.
- [Cockos forum "REAPER live band rig" thread](https://forum.cockos.com/archive/index.php/t-176792.html) (via search summaries; the archive itself is behind a bot-check): consensus that REAPER *can* do it via LiveConfigs but is **"clumsy compared to Forte or Cantabile"**, and that Ableton/MainStage are purpose-built with proven live reliability.
- [Cockos forum: "Best way to setup 70 songs setlist for live performance"](https://forums.cockos.com/showthread.php?t=229184) — the standard answers are regions + SWS Region Playlist + smooth seeking, one big project (RAM concerns) vs project-per-song (load-time concerns).
- The guitar-side equivalent, the [REAPER Live Pedalboard Project (pipelineaudio)](https://pipelineaudio.net/the-reaper-live-pedalboard-project/), is instructive as a **tried-and-moved-on** case: launched ~2018 on LiveConfigs + PC→CC JSFX + FCB1010, hit audio dropouts on patch switches with basic configs, added MIDI-crossfade plugins to get dropout-free switching, then the community "moved far, far on" to LBX Stripper; no visible updates since ~2019.
- There is at least one active Facebook-group thread ["Using Reaper for live performances with SWS live configs"](https://www.facebook.com/groups/222914377916832/posts/2965172347024341/) — the practice survives, but as a hacker path, not a product.

**Pattern:** everything that exists is *mute-based track switching* plus discipline. Nobody has productized it. The recurring pains: per-song tempo, PC→CC translation, macOS gaps, setup complexity, no polished setlist UI, no seamless-tail guarantees, and "roll your own backup plan."

---

## 2. Ableton-style clip/loop launching in REAPER

### 2.1 Playtime 2 (Helgoboss) — the only real clip launcher for REAPER

- **What it is:** a full session-view/clip-launcher **inside REAPER**, delivered via the Helgobox plugin (same package as ReaLearn). 8x8+ matrix of audio and MIDI clips, records and triggers clips, tempo-synchronized ("clips start on the next bar by default"), anacrusis support, customizable MIDI reset, multi-channel audio, time-stretch options, matrix sequencer, export-to-arrangement. Grid controllers (Launchpad-style) supported via ReaLearn. Source: [helgoboss.org/projects/playtime](https://www.helgoboss.org/projects/playtime).
- **State (as scraped 2026-08):** version **2.18.2 (released 2025-12-01)**; **€64.00 including VAT**; license covers all 2.x updates; free evaluation with **saving/loading disabled**; Windows 8+/macOS 10.15+; **Linux experimental** (stage 1 in 2.18.0). Roadmap: looper-style recording modes, automation clips, **follow actions** (not there yet), Linux completion.
- **Reputation:** the [KVR launch thread](https://www.kvraudio.com/forum/viewtopic.php?t=612569) is mixed-positive — praised for polish and for letting people "stay with Reaper and still get some kind of session view"; unique features vs Ableton (non-exclusive mode: multiple clips per column simultaneously); acknowledged **beta bugs**; developer Benjamin Klum is famously responsive (the [Cockos development thread](https://forum.cockos.com/showthread.php?p=2795683) ran 11+ pages of iteration). Historical live credibility is thin: Playtime 1 was used "for a couple of live streams during the pandemic" — there is no visible body of "we gig Playtime every weekend" testimony yet. It is positioned for "live performances, improvisation, jamming, looping and sketching," but its follow-actions gap and youth mean cover bands have not adopted it as a Playback/Ableton substitute.

### 2.2 Native/SWS options for triggering pre-recorded material

- **Regions + smooth seeking**: REAPER can defer a seek to the next measure/marker boundary — the foundation of every "jump to song section live" workflow. Tutorial: [Reaper Live Show Tutorial: Markers, Smooth Seeking, Regions, and SWS Extensions (YouTube)](https://www.youtube.com/watch?v=NueQXl6m-XI).
- **SWS Region Playlist**: ordered playlists of regions with repeat counts, played in any order irrespective of timeline position — Cubase-Arranger-style; documented in [Sound On Sound: "Power Arranging In Reaper"](https://www.soundonsound.com/techniques/power-arranging-reaper). Used by bands as a setlist player (append songs as regions, order per gig).
- **Action markers** (via Song Switcher's `!` take markers) to fire actions at timeline positions.
- Community scripts: [Floopa Station](https://floopreaperscript.gumroad.com/l/tiqprz) (looping), Stem Manager, various Gumroad playlist managers ([hosiprod PMP](https://hosiprod.gumroad.com/l/pmp)).
- Tutorial for the stems+click workflow: [Creating Backing Tracks with Click for Live Performance in REAPER (YouTube)](https://www.youtube.com/watch?v=jxVDe5ChvjQ) — stems left/mono mix + click on a separate output, one region per song.

### 2.3 What cover/worship bands actually run for backing tracks

- **Ableton Live** — repeatedly called the **industry standard** for live playback ([TalkBass thread](https://www.talkbass.com/threads/backing-tracks-for-live-performance-whats-good.1608589/), [Ableton forum: "Using Ableton with Live Band"](https://forum.ableton.com/viewtopic.php?t=246603), [Metropolis cover-band guide](https://www.metropolis-live.co.uk/blog/metropolis-band-blog/backing-tracks-cover-band-ableton-live)). Bands report "temperamental when powering everything on... super reliable once it's up and running"; standard tactics are stripping FX and **raising buffer size** since playback (not synth latency) is the job. Live Intro is $99; most track providers ship Ableton session templates.
- **Playback by MultiTracks.com** — the worship-market default player (iOS/macOS/PC). **Playback Premium from $9.99/month** (section rearranging, MIDI mapping, looping sections, infinite click, volume/mute automation); **Playback Rentals from $59.99/month for 16 song rentals**. Sources: [Playback subscriptions explained](https://helpcenter.multitracks.com/en/articles/8106819-playback-subscriptions-explained), [Playback rentals](https://helpcenter.multitracks.com/en/articles/5725263-get-started-playback-rentals).
- **Prime by Loop Community** — **free** player app (iOS/macOS), buy tracks individually; section jumping, key/tempo change, crossfade/loop on demand ([loopcommunity.com/prime](https://loopcommunity.com/en-us/prime-multitrack-app)).
- Market pricing context: worship multitrack subscriptions run **$60–$100/month** for limited rentals; buy-outright stems **$17–$30/song** ([Worship Leader magazine comparison](https://worshipleader.com/production/which-backing-track-provider-to-choose/), [Church Production: Playback vs Ableton](https://www.churchproduction.com/magazine/playback-vs-ableton-for-worship-multi-tracks-which-one-is-ri/)).
- **Hardware escape hatches** (for people who refuse laptops): Cymatic LP-16 (discontinued), Roland SPD-SX, Idoru P-1 ([Fractal forum thread](https://forum.fractalaudio.com/threads/backing-tracks-these-days.128406/), [drumspy guide](https://drumspy.com/academy/backing-tracks-player/)).

### 2.4 What REAPER would need to be trusted for this job

From the threads above, the trust checklist bands apply: (1) **section-quantized launching** that can never drift from the click; (2) **one-tap song select with zero disk hiccup**; (3) separate click/guide outputs and per-member cue mixes; (4) **it must recover instantly** — power-cycle to playing in under a minute; (5) a non-engineer must be able to run it. Ableton wins today on 1–3 and ecosystem; Playback/Prime win on 5. REAPER has all the primitives (regions, smooth seek, region playlist, multichannel outs, Playtime) but no packaged, opinionated layer — which is exactly the StageRig gap.

---

## 3. The reliability bar for live rigs

### 3.1 Latency and audio-device settings

- Latency math: **128 samples @ 44.1 kHz = 2.9 ms** buffer latency; sub-3 ms is imperceptible, 3–10 ms perceivable by some. Live players typically run **64–256 samples @ 44.1/48 kHz**; smaller buffers = higher CPU pressure = higher spike risk. Sources: [Gig Performer: Audio latency, buffer size and sample rate explained](https://gigperformer.com/audio-latency-buffer-size-and-sample-rate-explained), [GP Windows optimization guide](https://gigperformer.com/docs/ultimate-guide-to-optimize-windows-for-stage/buffersizesamplerate.html).
- Test **every** plugin at the stage buffer size before the gig; plugins that behave at 512 can glitch at 128 ([Ableton rig build guide](https://lofimonster.com/blog/ableton-live-performance-rig-build) — which also reports M2/M3 Macs running ~40–50% lower CPU load than comparable Intel machines at the same buffer, directly reducing dropout risk).

### 3.2 How MainStage earns "seamless"

- MainStage's headline live feature: **patch switching sustains the previous patch's notes while you play the new one** — held notes ring out naturally across the switch with zero programming. The catch: **pedal-sustained** sound does *not* carry across a patch change by default; the community workaround is pasting an alias of the old patch's channel strip into the next patch. Sources: [brianli.com: How to Sustain Sound Over Patch Changes in MainStage](https://brianli.com/how-to-sustain-sound-over-patch-changes-in-mainstage/), [Apple MainStage User Guide](https://help.apple.com/pdf/mainstage/en_US/mainstage-user-guide.pdf), [LiveKeyboardist: recreating MainStage-style smooth patch changes in Ableton](https://livekeyboardist.com/smoothpatchchanges/) (proof this behavior is the benchmark other rigs imitate).
- The dedicated hosts' answer to RAM-vs-instant-switching: **Gig Performer "Predictive Loading"** keeps the current rackspace plus a window of ±2 (setlist-aware: current fully loaded, then next, then previous) loaded in RAM, swapping in the background without touching audio ([GP docs](https://gigperformer.com/docs/GP4UserManual/predictive-loading.html), [GP blog](https://gigperformer.com/predictive-loading-in-gig-performer)); **Cantabile "pre-load set list"** loads every song/rack in the setlist up front and encourages shared "racks" so one plugin instance serves many songs ([Cantabile set lists guide](https://www.cantabilesoftware.com/guides/setLists)).

### 3.3 REAPER's equivalent constraints (the technical crux for StageRig)

- **Everything preloaded, switching = muting.** Both LiveConfigs and Song Switcher keep all patches instantiated and switch by mute/unmute with the global **Track mute fade (recommended 100 ms)**. There is a built-in tension: "**Do not process muted tracks**" saves CPU but means a muted patch's reverb/delay **tails are killed** — the opposite of MainStage's ring-out. A MainStage-grade REAPER rig must leave recently-active tracks processing (or delay their mute) and eat the CPU. (LiveConfigs PDF, Song Switcher docs, cited above.)
- **Anticipative FX processing** (Preferences > Audio > Buffering) is REAPER's render-ahead trick for low CPU — but it adds latency paths and is **automatically bypassed for record-armed/monitored tracks**; the [REAPER Troubleshooting Guide](https://www.reaper.fm/guides/ReaperTroubleshootingGuide.pdf) and the [anticipative-FX forum thread](https://forum.cockos.com/archive/index.php/t-143722.html) recommend disabling it (or "Allow live FX multiprocessing" instead) for live-input work. A live rig is essentially all-monitored-tracks, so REAPER runs without its main CPU-saving machinery — sizing headroom matters.
- **ReaScript defer ≈ 30 ms:** deferred scripts run at ~30–50 Hz (commonly stated ~33 Hz max), so any *script-driven* switching/UI logic carries 20–33 ms of added jitter — fine for setlist navigation, not fine in the note path. LiveConfigs avoids this by being a native C++ extension. Sources: [Cockos forum "Defer() speed"](https://forum.cockos.com/archive/index.php/t-168270.html), [ReaScript docs](https://www.reaper.fm/sdk/reascript/reascript.php).
- Also required (LiveConfigs checklist, §1.1): audio device never closed when inactive, Run FX when stopped, undo off, dedicated `-cfgfile` live profile so studio settings can't leak onto stage.

### 3.4 Backup strategy norms

- The LiveConfigs author's golden rule: *"I must have a backup solution ready to go — even if totally degraded"* (even a single hardware patch or an mp3 of the tracks).
- Working pros describe MainStage failures as interface-level (e.g., intermittent MOTU disconnects mid-show) as much as software crashes — [Apple Community: "MainStage 3 – Not a reliable software"](https://discussions.apple.com/thread/7493799), ["Is Mainstage Useless. If it's not 100% reliable…"](https://discussions.apple.com/thread/4010817). Hence the norms: identical mirrored laptop where budget allows, hardware synth or track-player fallback otherwise, and power-on-to-playing rehearsed as a drill. Ableton bands echo the same: fragile at power-up, solid once running ([Ableton forum](https://forum.ableton.com/viewtopic.php?t=232732)).

---

## 4. The market

### 4.1 MainStage: huge installed base, visible neglect

- **Price: $29.99** on the Mac App Store ([App Store listing](https://apps.apple.com/ca/app/mainstage/id634159523?mt=12&see-all=reviews&platform=mac)) — an order of magnitude cheaper than every rival, which is why it's the default, especially in the **worship market** (the single biggest identifiable segment of laptop keyboardists).
- **Neglect signals:** community thread ["Has MainStage been abandoned?"](https://discussions.apple.com/thread/255889198) (a year+ without updates while Logic gets features; "the MainStage team is quite small"); update-breaks-concerts threads ([3.6 crashing](https://discussions.apple.com/thread/254944329), [3.6 update crashes](https://discussions.apple.com/thread/253744683)). The 3.7 update ([Logic Studio Training summary](https://logicstudiotraining.com/mainstage-3-7-update/)) added Logic hand-me-downs (Quantec reverb, ChromaGlow, plugin search) — welcomed precisely because updates are so rare.
- **Structural complaints:** macOS-only, **AU-only** plugin support, "Limited" rig management ([Gig Performer's comparison table](https://gigperformer.com/gig-performer-vs-mainstage-vs-cantabile-vs-camelot-pro)); pros running tracks increasingly default to Ableton instead.

### 4.2 What alternatives cost (the price umbrella StageRig sits under)

| Product | Price | Platform | Notes |
|---|---|---|---|
| MainStage 3.7 | **$29.99** | macOS only | AU only; [App Store](https://apps.apple.com/ca/app/mainstage/id634159523) |
| Gig Performer 5 Pro | **$169** (single OS) / $199 both; Essentials **$59** | Mac+Win | 5 activations, perpetual; [store](https://gigperformer.com/store), [Essentials launch](https://www.synthtopia.com/content/2025/07/17/gig-performer-essentials-now-available/) |
| Cantabile | Solo **~$69**, Performer **~$199–200**; updates $39/$99 per yr after year 1; Lite free | **Windows only** | [purchase](https://www.cantabilesoftware.com/purchase/), [subscription model](https://www.cantabilesoftware.com/guides/subscriptions) |
| Camelot Pro | **$149** desktop; **$29.99** iPad; $49 bundled with a SWAM instrument | Mac+Win+iOS | [Sweetwater](https://www.sweetwater.com/store/detail/CamelotPro--audio-modeling-camelot-pro-live-performance-environment-software), [audiomodeling.com](https://audiomodeling.com/camelot/overview/) |
| Playtime 2 (REAPER) | **€64** | Mac+Win (+Linux exp.) | clip launcher, not a patch host; [helgoboss.org](https://www.helgoboss.org/projects/playtime) |
| REAPER itself | $60 discounted license | Mac+Win+Linux | the whole DAW under every StageRig idea |
| Playback Premium / Rentals | $9.99/mo / from $59.99/mo | iOS/macOS/PC | tracks player only; [MultiTracks help](https://helpcenter.multitracks.com/en/articles/8106819-playback-subscriptions-explained) |
| Ableton Live Intro+ | $99+ | Mac+Win | tracks + clips standard; [Metropolis guide](https://www.metropolis-live.co.uk/blog/metropolis-band-blog/backing-tracks-cover-band-ableton-live) |

(Legacy host **Forte** by Brainspawn still comes up in old threads as the thing people compared REAPER against; it is no longer a going concern in current comparisons.)

### 4.3 Where these players hang out

- **Forums:** [The Keyboard Corner (Music Player Network)](https://forums.musicplayer.com/topic/179516-dilemma-cantabile-gig-performer-camelot-pro/) — the classic gigging-keyboardist forum, where "Cantabile vs Gig Performer vs Camelot" dilemma threads live; [Gig Performer Community](https://community.gigperformer.com/); [Cantabile Community](https://community.cantabilesoftware.com/); [Cockos REAPER forum](https://forum.cockos.com/); [KVR Hosts & Applications](https://www.kvraudio.com/forum/); Gearspace live-sound and keyboard boards; Apple Communities (MainStage).
- **Facebook groups:** [Mainstage Users Group](https://www.facebook.com/groups/mainstageusersgroup/), [MainStage Worship Sounds](https://www.facebook.com/groups/MainStageWorshipSounds/), [Gig Performer group](https://www.facebook.com/groups/gigperformer/), REAPER users groups (live-performance posts appear there).
- **Reddit:** r/mainstage, r/Reaper, r/worshiponline-adjacent subs, r/livesound.
- **YouTube/vendors shaping the worship segment:** [Sunday Sounds / Sunday Keys](https://sundaysounds.com/pages/sunday-keys) (450+ worship patches, MainStage *and* Ableton templates — note they hedge across both hosts), [Worship Online free MainStage patches](https://worshiponline.com/free-mainstage-patches-for-worship/), Churchfront, [The REAPER Blog](https://reaper.blog/) on the REAPER side.
- No public number exists for "how many keyboardists use MainStage," but the proxy signals are strong: a $30 app with an entire third-party patch economy (Sunday Sounds, Worship Online, MultiTracks' ecosystem), multiple dedicated Facebook groups, and every rival ([Gig Performer's comparison pages](https://gigperformer.com/how-does-gig-performer-compare)) positioning against it as the incumbent.

---

## 5. Synthesis: the gap StageRig would fill

1. **REAPER-as-live-rig is proven possible but never productized.** LiveConfigs (2012 docs, CC-only, macOS gaps) and Song Switcher (mute/hide folder tracks) are the state of the art; both are mute-based switchers demanding expert setup, and the one big community project (Live Pedalboard) stalled and migrated away.
2. **The MainStage behavior to match is specific and testable:** old patch rings out (including pedal sustain), new patch instantly playable, zero click, sub-3 ms feel at 128/44.1, everything preloaded — with GP's predictive loading and Cantabile's pre-load setlists as the RAM-management prior art.
3. **REAPER's hard constraints are known:** anticipative FX effectively off for monitored tracks, mute-fade vs kill-tails tension, ReaScript's ~30 ms defer tick (native extension or JSFX needed in the note path), audio device must never close, undo off, dedicated live config profile.
4. **For loops/backing tracks,** Playtime 2 (€64, v2.18.2, active dev, no follow actions yet, thin gig track-record) plus SWS Region Playlist are the raw materials; the trusted incumbents to beat are Ableton (industry standard) and Playback/Prime (worship default, subscription-priced).
5. **Price umbrella:** $59–$199 is the accepted range for a serious live host; MainStage's $29.99 anchors the low end; worship teams already pay $60–100/month for tracks — a one-time StageRig price inside that range is credible.
