# NPH BUSINESS BRIEF — YouTube, Course, Website

**Owner:** Jason Zac / Nathaniel School of Music (music@nathanielschool.com)
**Date:** 25 July 2026
**Companion file:** `NPH_TECH_BRIEF.md` (same folder) — the REAPER engineering brief.

---

## 0. READ THIS FIRST — what this file is NOT

This file contains **no REAPER API work, no Lua, no test harness.** If you find
yourself debugging a script, you are in the wrong document — switch to
`NPH_TECH_BRIEF.md` and start a separate session.

The owner asked explicitly for these two tracks to be kept apart, and he is right
to. They fail differently. Engineering has a correctness gate: a harness either
returns `0 failed` or it does not. Business work has no such gate — it is writing,
design, pricing, and taste, and if you mix it into an engineering session it will
quietly eat the session's attention and neither will get finished.

**One session, one track. Never both.**

---

## 1. WHO HE IS — the asset nobody else has

This matters more than any feature list, so internalise it before writing a word of
copy.

Jason Zac runs the Nathaniel School of Music. He is not a plugin developer who
happens to make music. He is a **working producer and educator with a decade of
released, credited work** — Lagori, Rudy Wallang, Soul Circle Collective, an MJ
tribute show, plus roughly eighty riff and tutorial project folders. He plays live.
He has years of real MainStage concert files from real gigs.

And he built these tools **because his own sessions were slow**, not because he
surveyed a market.

**That is the moat, and it is the only thing in this whole plan that cannot be
copied.** Anyone can write a REAPER script. Nobody else can teach REAPER using a
decade of their own released records and the tools they built to make them. Every
piece of business output below should be pointed at that fact. If a video, a course
module, or a web page could have been made by someone who has never shipped a
record, it is off-brand and should be rewritten.

**Tone rule:** he is not a guru and should not sound like one. The voice is a
working professional showing you his actual desk. Specific, unhurried, slightly
opinionated, allergic to hype. No "10x your workflow" thumbnails. No countdown
timers. No fake scarcity.

---

## 2. TRACK A — YOUTUBE

### Why YouTube first
It is the only one of the three that generates demand rather than converting it.
The website and the course both need traffic that already believes he is worth
listening to. YouTube is where that belief gets manufactured. **Build this first,
even though it feels least like progress.**

### The format that fits him
Not tutorials. **Session footage with commentary.** The strongest possible video
for this project is not "10 REAPER tips" — it is him opening a real Lagori session
and organising it in front of you, hands on the keyboard, using the shortcuts. The
tools appear as a consequence of the work, not as the subject.

Three video shapes, in priority order:

**Shape 1 — "Watch me do the boring part."** The full, unglamorous session-prep
ritual, uncut, at real speed: import, name, colour, folder, mark sections, set
tempo. Eight to fourteen minutes. This is the flagship shape and it should be the
first video. It demonstrates every tool in the suite without a single moment of
selling, and it is unfakeable by anyone who does not actually work this way.

**Shape 2 — "This is broken and here is why."** A single REAPER frustration, its
actual root cause, and the fix. The Cowork session generated a lot of real material
of this exact kind — custom actions silently flipping global preferences, tempo
markers landing off the bar line, `.ReaperKeyMap` imports that can never modify an
existing custom action. **These are genuinely good videos** because almost nobody
else has done the forensic work. Three to six minutes each. High search value.

**Shape 3 — "The live rig."** Reserved until StageRig actually exists. When it does,
this becomes the biggest video on the channel, because "I replaced MainStage" is a
headline with a real audience behind it. **Do not make this video early.** A demo of
something not yet finished will burn the strongest card in the deck.

### First six videos — a concrete slate
1. **The session-prep ritual, uncut.** (Shape 1. The channel's anchor.)
2. **"Your custom actions are lying to you."** How a single step buried in a REAPER
   custom action was centring every pan in the session, and how to audit your own.
   (Shape 2 — this is a true story from the audit and it is a strong hook.)
3. **"Why your tempo marker won't stay put."** The unquantized-edit-cursor problem,
   demonstrated live, then fixed. (Shape 2.)
4. **Colour and naming as a *thinking* tool**, not decoration. Palette & Look shown
   in a real session. (Shape 1.)
5. **The sixteen keys.** His actual non-standard shortcut layout and the reasoning
   behind each choice. Honest about the tradeoffs of non-traditional bindings.
6. **Folders in REAPER: the three things that always go wrong.** Ties directly to
   the Folders & Flow app when it ships. (Shape 2.)

### Production rules
- **Publish on a cadence you can survive.** One video a fortnight, sustained for six
  months, beats six videos in three weeks and then silence. The algorithm punishes
  the gap far more than it rewards the burst.
- Record at the resolution the REAPER UI is actually readable at. Small text is the
  single most common failure in DAW videos.
- Every video ends pointing at **one** thing — daw.nathanielschool.com. Not the
  course, not a donation link, not a Patreon. One destination.
- Do **not** gate anything behind a like or a subscribe. It is off-brand.
- Description of every video carries the ReaPack repository URL. Free tools in the
  description is what converts a viewer into a user.

### What to hand an agent for this track
Ask it to: draft titles and descriptions from a supplied outline; write the shot
list for a specific video; research what already exists on YouTube for a given
REAPER topic and where the gap is; build the channel's about page and banner copy.
**Do not** ask it to write the script word-for-word — the value of the channel is
that it sounds like him, and a fully written script will not.

---

## 3. TRACK B — THE COURSE

**Home:** learnmusic.nathanielschool.com

### The positioning
Not "learn REAPER." The internet has that, free, and Kenny Gioia has owned it for a
decade. There is no version of this course that wins by being a better manual.

The positioning that wins is **"how a working producer actually runs a session"** —
speed, organisation, and delivery, taught through his own released projects, with
the tools he built as the vehicle. The REAPER knowledge is the medium. The
professional workflow is the product.

Say the quiet part in the sales copy: this is not for beginners looking for a
feature tour. It is for people who already use a DAW and are slow in it.

### Structure — eight modules, each mapped to an app
This mapping already exists in the tech plan and it is a good spine, because each
module has a concrete artefact the student installs and uses.

1. **The speed layer.** The sixteen keys. Why non-traditional bindings, and how to
   design your own. Ends with the student's own keymap file.
2. **Track organisation and colour.** Palette & Look. Colour as navigation.
3. **Folders and signal flow.** Folders & Flow. Fixing broken nesting.
4. **Sections and time.** Markers, regions, tempo maps that hold.
5. **Render and deliver.** Stem Print & Handoff. Stems that a mixer will not send
   back.
6. **Recording sessions at speed.** The whole ritual end to end, on a real project.
7. **Collaboration and handoff.** Templates, track settings transfer, project
   portability.
8. **Live: StageRig.** The capstone. Gated on the app actually existing.

**Ship modules 1–4 first as a complete standalone product.** Do not wait for eight.
A four-module course that exists beats an eight-module course that is perpetually
"nearly ready," and modules 5–8 become the upgrade path.

### Pricing — the owner's call, these are only anchors
The tools should be cheap or free; the course carries the margin. Software has a
race to the bottom in this market and teaching does not.

Indicative, **not a forecast**: the course in the $149–299 band, with a lower launch
price for the first cohort in exchange for testimonials and feedback. Bundle the pro
tools with the course rather than selling them hard separately — it makes the course
the obvious purchase and the tools the reason to trust it.

**Legal/financial note:** none of the numbers in this file are financial advice or
projections. They are anchors for a decision that is his to make, and he should
sanity-check pricing against his own audience size and what his existing school
students already pay.

### The honest risk
The course depends on apps that, as of this writing, are mostly not built. Modules
3, 4, 5 and 8 all reference software that is design-only or unverified. **Do not
record a module for an app that does not exist and work.** The fastest way to
destroy the credibility that the whole plan rests on is to teach a tool the student
then cannot use.

Sequence: build the app → verify it in a real session → record the module.

---

## 4. TRACK C — daw.nathanielschool.com

### The question the site has to answer in five seconds
He put it exactly right: *"why would people go to daw.nathanielschool.com?"*

The answer is **not** "to read about a REAPER suite." It is:

> **This is where the REAPER tools live that a working producer built for his own
> sessions — and where you can watch him use them.**

The site's job is to be the one place where the tools, the proof they work, and the
person who made them sit together. YouTube proves the person. ReaPack delivers the
tools. The site is where those two meet and where the course gets sold.

### Page structure

**Home.** Above the fold: one sentence of positioning, one screenshot or short
looping clip of an app *in a real session* (not a mock, not a feature grid), and one
button — install via ReaPack. Below that: the apps, each with its accent colour
(green = structure, amber = delivery, violet = performance, teal = look), a
one-line statement of the problem it solves, and its honest status. **Ship the
status honestly** — "in development" on StageRig builds more trust than a fake
"coming soon" polish.

**One page per app.** The problem in the user's words, the fix, a short clip, the
install line, the changelog. These pages are what rank in search over time, and they
are what a skeptical REAPER forum user opens before deciding whether to trust the
repo.

**A "why these exist" page.** This is the page most tool sites do not have and it is
the one he can write better than anyone. The custom-action audit story — real bugs,
real root causes, real measurements — is genuinely compelling engineering writing
and it does the trust-building that no amount of feature copy can.

**Course page** pointing to learnmusic.nathanielschool.com.

**Donate.** Quiet, not begging. A line about what donations fund (time to keep the
free core maintained) and a link. The `@donation` header in the ReaPack metadata
should point here.

### Distribution mechanics that belong to this track
- **The free core on ReaTeam/ReaScripts is the single biggest distribution lever
  available.** Getting the twelve-script speed layer accepted into the community
  collection puts it in front of every ReaPack user by default. Nothing else on this
  list compares. Treat acceptance there as a business objective, not a technical one.
- **Precedent to study: X-Raym / ExtremRaym.** Large free open-source pack building
  reputation and reach, plus premium script packs sold from his own site. That is
  exactly this shape, already proven in this exact market. Study his site structure,
  his free/paid line, and his donation framing before designing ours.
- Free/pro split: free core on ReaTeam (MIT or GPL) as marketing that must be
  genuinely excellent; pro tier delivered as a **private unlisted ReaPack URL** given
  to buyers. Indicative anchors, his call: $19–29 per app, $59–79 bundle, StageRig
  $79–129.
- The public repository list at reapack.com/repos is worth being on.

### What to hand an agent for this track
Building the site is a good agent job — it is self-contained, has clear structure,
and no correctness gate to fake. Hand it: the page structure above, the colour
language, the app inventory and honest statuses from the tech brief's §5, and ask
for a static site. Ask it to write the app pages from the real bug findings rather
than from marketing adjectives.

---

## 5. SEQUENCING — what actually happens first

The three tracks are not equal and should not run in parallel.

**Now, while the apps are still being built:** YouTube videos 2 and 3, the "this is
broken and here is why" shape. They need no finished software — the forensic
material already exists and is genuinely interesting. They start building the
audience during the months when engineering is the bottleneck.

**When the free core ships on ReaPack:** the site's home page and app pages, because
now there is something to install. Submit to ReaTeam the same week. Video 1, the
session-prep ritual, lands alongside as the anchor.

**When modules 1–4's apps are all verified working:** record and sell the course.
Not before.

**When StageRig exists and has survived a real gig:** the live video, and the
capstone module. This is the biggest card in the deck and it should be played last
and once.

---

## 6. WHAT TO ASK AN AGENT FOR IN THIS TRACK — and what not to

**Good agent work here:** competitive research on what exists in the REAPER
education and script market; drafting page copy and app-page structure; building the
static site; writing video titles, descriptions and shot lists; designing the course
outline in detail; studying the X-Raym precedent and reporting the structure;
drafting the ReaTeam submission.

**Bad agent work here:** anything that has to sound like him in his own voice —
video narration, the "why these exist" essay, course teaching scripts. An agent will
produce competent, generic prose and the whole strategy above depends on the output
being unfakeably personal. Have it draft structure and research; he writes the
sentences that carry the voice.

**Never in this session:** touching a `.lua` file.
