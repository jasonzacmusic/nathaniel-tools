-- @description Track Settings Transfer
-- @version 2.1.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about Pro-Tools style "Import Session Data" between open project tabs.
--   Copies FX chains, volume, pan, sends, colour and input FX from the tracks
--   of one project onto the same-named tracks of one or more other tabs, or
--   builds the tracks that are missing. Preview first; one undo point per
--   target project. Automation is never copied.
--   Requires the "Shared Libraries" package from this same repository and the
--   SWS extension. ReaPack has no automatic dependencies, so install the
--   libraries too - or right-click the repository in ReaPack > Install All.
-- @changelog
--   2.1.0 - the From / To / what-to-copy setup folds into one line so the track list
--           gets the room in the docker; opens docked by default.
--   2.0.0 - new shared look (nt_ui): header, sections, one status line + log,
--           plain-English tags (exact / guess / picked / new / none) instead of
--           the cryptic = ~ * +. Name guessing fixed: two tracks that merely
--           share an instrument family (Kick vs Snare) no longer count as
--           "similar", so Kick's FX and sends can never land on Snare, and
--           Build mode now builds Kick instead of skipping it. Guesses (amber)
--           start OFF - you tick the ones that are right. TRANSFER asks first
--           and says exactly what it replaces and where. Two rows aimed at the
--           same target track are flagged and block the transfer. Built tracks
--           no longer inherit mute / solo / record / selection / automation-
--           mode state from the source. Preview and Transfer no longer flash
--           through the other tab. "Selected" keeps your remaps and FX / Vol /
--           Pan / Sends ticks. The change watcher now also notices folder
--           changes. The compare target is a visible "Compare with" switch.
--           Starts with one tab open and tells you what to do, instead of
--           refusing to launch.
--   1.0.0 - first public release.

--[[
  Track Settings Transfer  -  REAPER / ReaImGui
  ------------------------------------------------------------------------------
  Pro-Tools "Import Session Data", dockable, across ANY open project tabs.

  FROM one project  ->  TO one or more projects.
    * Tracks are matched by name: same name = "exact"; a look-alike name
      ("Lead Vox" ~ "Lead Vocal", "Bass DI" ~ "Bass D.I.") = "guess".
    * Guesses start UNTICKED. Tick the ones that are right, or pick a
      different target from the row's combo ("picked").
    * Per row: FX / Vol / Pan / Sends. Plus Colour and Input FX for all rows.
    * Build missing tracks: a From track with no match is created in the To
      project - name, colour, FX, volume, pan, folder position - then its
      sends are rebuilt.
    * Several To projects at once: the list is checked against the project
      under "Compare with"; the other To projects get exact-name matches only.

  Never copies automation. Preview changes nothing. One undo point per target.
  TRANSFER always asks first, because it replaces FX chains and removes the
  existing sends on every target track it writes to.

  Safety: the window stores GUIDs only, never MediaTrack* / ReaProject*.
  Pointers are resolved and validated immediately before use (nt_safe).
  Change watching uses safe.projSignature (add / delete / rename / reorder /
  folder), not GetProjectStateChangeCount, which does not move for those.

  Requires ReaImGui, SWS and the Shared Libraries package.
--]]

local r = reaper

--------------------------------------------------------------------------------
-- libraries
--------------------------------------------------------------------------------
do
  local sep = package.config:sub(1, 1)
  local here = ({ r.get_action_context() })[2]:match("(.*" .. sep .. ")") or ""
  package.path = here .. ".." .. sep .. "scripts" .. sep .. "lib" .. sep .. "?.lua;" ..
                 r.GetResourcePath() .. "/Scripts/Nathaniel Tools/scripts/lib/?.lua;" ..
                 package.path
end
local okSafe, safe = pcall(require, "nt_safe")
local okUi,   ui   = pcall(require, "nt_ui")
if not (okSafe and okUi) then
  r.ShowMessageBox("Track Settings Transfer needs the 'Shared Libraries' package.\n\n" ..
    "Extensions > ReaPack > Browse packages > search 'Nathaniel Tools' > Shared Libraries > Install.\n" ..
    "(Or right-click the Nathaniel Tools repository > Install All.)", "Track Settings Transfer", 0)
  return
end
do local ok, compat = pcall(require, "nt_imgui"); if ok then compat.install() end end
if not safe.require("Track Settings Transfer", { imgui = true, sws = true }) then return end

local APP = "Track Settings Transfer"
local T = ui.tokens
local SIM_THRESHOLD = 0.55

--------------------------------------------------------------------------------
-- string / similarity
--------------------------------------------------------------------------------
local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
local function norm(s) return trim((s or ""):lower():gsub("%s+", " ")) end
local function core(s)
  s = (s or ""):lower():gsub("[^%w]+", " ")
  local out = {}
  for tok in s:gmatch("%S+") do if not tok:match("^%d+$") and #tok > 1 then out[#out + 1] = tok end end
  return table.concat(out, " ")
end
local function tokenSet(c) local t = {} for w in c:gmatch("%S+") do t[w] = true end return t end
local function jaccard(a, b)
  local seen, inter, uni = {}, 0, 0
  for k in pairs(a) do seen[k] = true end
  for k in pairs(b) do seen[k] = true end
  for k in pairs(seen) do uni = uni + 1; if a[k] and b[k] then inter = inter + 1 end end
  return uni == 0 and 0 or inter / uni
end
local LEV_CAP = 64
local function levenshtein(a, b)
  if a == b then return 0 end
  if #a > LEV_CAP then a = a:sub(1, LEV_CAP) end
  if #b > LEV_CAP then b = b:sub(1, LEV_CAP) end
  if #a == 0 then return #b end
  if #b == 0 then return #a end
  local prev, cur = {}, {}
  for j = 0, #b do prev[j] = j end
  for i = 1, #a do
    cur[0] = i; local ca = a:byte(i)
    for j = 1, #b do
      local cost = (ca == b:byte(j)) and 0 or 1
      local del, ins, sub = prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost
      local m = del < ins and del or ins
      cur[j] = m < sub and m or sub
    end
    for j = 0, #b do prev[j] = cur[j] end
  end
  return prev[#b]
end

-- Instrument families: names in the same family are RELATED, not the same.
local ROLE_ALIASES = {
  acoustic = { "acoustic", "aco", "nylon", "steel", "folk" },
  drums    = { "drum", "drums", "kit", "kick", "snare", "snr", "hat", "hihat", "tom", "floor", "overhead", "room", "cymbal", "ride", "crash", "perc", "percussion", "clap", "shaker" },
  bass     = { "bass", "808", "sub" },
  guitar   = { "guitar", "gtr", "electric", "elec", "dist", "distortion", "drive", "overdrive", "crunch", "heavy", "riff", "strat", "tele", "lespaul" },
  vocal    = { "vocal", "vox", "voice", "bgv", "harmony", "choir", "adlib" },
  keys     = { "keys", "piano", "pno", "rhodes", "wurli", "wurlitzer", "organ", "clav", "clavinet" },
  synth    = { "synth", "pad", "pads", "poly", "arp", "pluck" },
  strings  = { "strings", "violin", "cello", "viola", "orchestra" },
  brass    = { "brass", "horn", "horns", "trumpet", "sax", "trombone" },
  wind     = { "flute", "whistle", "melodica", "clarinet", "oboe", "recorder" },
}
-- Fixed walk order so "Acoustic Gtr" always resolves the same way (pairs()
-- order is not fixed in Lua).
local FAMILY_ORDER = { "acoustic", "drums", "bass", "guitar", "vocal", "keys", "synth", "strings", "brass", "wind" }
local ROLE_TOKENS = { ac = "acoustic", ep = "keys", od = "guitar", gt = "guitar", bs = "bass" }
local TOKEN_ORDER = { "ac", "ep", "od", "gt", "bs" }

local function roleOf(name)
  local low = (name or ""):lower()
  local toks = {}
  for t in low:gmatch("%a+") do toks[t] = true end
  for _, tk in ipairs(TOKEN_ORDER) do if toks[tk] then return ROLE_TOKENS[tk] end end
  for _, fam in ipairs(FAMILY_ORDER) do
    for _, w in ipairs(ROLE_ALIASES[fam]) do if toks[w] then return fam end end
  end
  for _, fam in ipairs(FAMILY_ORDER) do
    for _, w in ipairs(ROLE_ALIASES[fam]) do
      if #w >= 4 and low:find(w, 1, true) then return fam end
    end
  end
  return nil
end

-- convention: a fully-UPPERCASE name is a bus / folder
local function isBusName(name)
  return name ~= "" and name == name:upper() and name:find("%u") ~= nil
end

-- How alike are two track names?  0 = nothing in common, 1 = the same name.
--   one inside the other     "Kick" ~ "Kick In"           0.85
--   shared words + spelling  "Lead Vox" ~ "Lead Vocal"    about 0.5
--   same instrument family   "Kick" ~ "Snare"             adds a LITTLE
-- The family can never make two names "similar" on its own: a pure family
-- match scores 0.30, well under SIM_THRESHOLD (0.55). Version 1 gave it 0.70,
-- which made Kick a "similar" match for Snare - so Kick's FX chain and sends
-- were written onto the first drum track found, and Build mode never built it.
local FAMILY_BONUS, FAMILY_ONLY = 0.15, 0.30
local function similarity(a, b)
  local ca, cb = core(a), core(b)
  if ca == "" or cb == "" then ca, cb = norm(a), norm(b) end
  if ca == "" or cb == "" then return 0 end
  if ca == cb then return 1 end
  local contain = (ca:find(cb, 1, true) or cb:find(ca, 1, true)) and 0.85 or 0
  local jac = jaccard(tokenSet(ca), tokenSet(cb))
  local maxlen = math.max(#ca, #cb)
  local lev = maxlen > 0 and (1 - levenshtein(ca, cb) / maxlen) or 0
  local resemblance = math.max(contain, 0.5 * jac + 0.5 * lev)
  local ra, rb = roleOf(a), roleOf(b)
  local sameFamily = ra ~= nil and ra == rb
  local bonus = sameFamily and FAMILY_BONUS or 0
  if isBusName(a) ~= isBusName(b) then bonus = bonus * 0.5 end
  local score = resemblance + bonus
  if sameFamily and score < FAMILY_ONLY then score = FAMILY_ONLY end
  if score > 1 then score = 1 end
  return score
end

--------------------------------------------------------------------------------
-- chunk helpers
--------------------------------------------------------------------------------
local function splitLines(chunk)
  local t = {}; for line in (chunk .. "\n"):gmatch("(.-)\n") do t[#t + 1] = line end; return t
end
local function findBlockEnd(lines, s)
  local depth = 0
  for i = s, #lines do
    local f = lines[i]:match("^%s*(.)")
    if f == "<" then depth = depth + 1
    elseif f == ">" then depth = depth - 1; if depth == 0 then return i end end
  end
end
local function findBlock(lines, pat)
  for i = 1, #lines do if lines[i]:match(pat) then local e = findBlockEnd(lines, i); if e then return i, e end end end
end
local function stripParmEnv(fx)
  local out, i = {}, 1
  while i <= #fx do
    if fx[i]:match("^%s*<PARMENV") then local e = findBlockEnd(fx, i); i = (e or i) + 1
    else out[#out + 1] = fx[i]; i = i + 1 end
  end
  return out
end
local function getBlock(proj, track, pat)
  if not safe.trackAlive(proj, track) then return nil end
  local ok, chunk = r.GetTrackStateChunk(track, "", false)
  if not ok then return nil end
  local lines = splitLines(chunk)
  local s, e = findBlock(lines, pat)
  if not s then return nil end
  local b = {}; for i = s, e do b[#b + 1] = lines[i] end; return b
end
local function setBlock(proj, track, pat, blk)
  if not safe.trackAlive(proj, track) then return false end
  local ok, chunk = r.GetTrackStateChunk(track, "", false)
  if not ok then return false end
  local lines = splitLines(chunk)
  local s, e = findBlock(lines, pat)
  local out = {}
  if s then
    for i = 1, s - 1 do out[#out + 1] = lines[i] end
    for _, l in ipairs(blk) do out[#out + 1] = l end
    for i = e + 1, #lines do out[#out + 1] = lines[i] end
  else
    local at
    for i = 1, #lines do if lines[i]:match("^%s*<ITEM") then at = i; break end end
    if not at then for i = #lines, 1, -1 do if lines[i]:match("^%s*>%s*$") then at = i; break end end end
    at = at or #lines
    for i = 1, at - 1 do out[#out + 1] = lines[i] end
    for _, l in ipairs(blk) do out[#out + 1] = l end
    for i = at, #lines do out[#out + 1] = lines[i] end
  end
  return r.SetTrackStateChunk(track, table.concat(out, "\n"), false)
end
local FXCHAIN_PAT     = "^%s*<FXCHAIN%s*$"
local FXCHAIN_REC_PAT = "^%s*<FXCHAIN_REC"

-- For BUILD: keep name / colour / FX / volume / pan / folder position.
-- Drop items, automation, receives, and every piece of "live state" the new
-- track must NOT inherit: mute/solo, record arm/input/monitor, selection,
-- free item positioning and automation mode.
local function cleanChunkForBuild(chunk)
  local lines = splitLines(chunk)
  local out, i = {}, 1
  while i <= #lines do
    local l = lines[i]
    if l:match("^%s*<ITEM") or l:match("^%s*<%u*ENV") then
      local e = findBlockEnd(lines, i); i = (e or i) + 1
    elseif l:match("^%s*AUXRECV") or l:match("^%s*MUTESOLO%s") or l:match("^%s*REC%s")
        or l:match("^%s*SEL%s") or l:match("^%s*FREEMODE%s") or l:match("^%s*AUTOMODE%s") then
      i = i + 1
    else
      out[#out + 1] = l; i = i + 1
    end
  end
  local s = table.concat(out, "\n")
  -- give the built track its own identity (function form: a '%' can never
  -- reach the pattern engine)
  s = s:gsub("TRACKID%s+{%x+%-%x+%-%x+%-%x+%-%x+}", function() return "TRACKID " .. r.genGuid("") end)
  return s
end

--------------------------------------------------------------------------------
-- projects / tracks
--------------------------------------------------------------------------------
local function densestOther(exclude)
  local best, bestN = nil, -1
  for _, p in ipairs(safe.openProjects()) do
    if p.proj ~= exclude and p.tracks > bestN then bestN = p.tracks; best = p.proj end
  end
  return best
end

--------------------------------------------------------------------------------
-- matching
--   mapsFor(proj, byGuid): keys are GUIDs (safe to store) or live MediaTrack*
--   (only ever used inside the same call stack).  findTarget is key-agnostic.
--------------------------------------------------------------------------------
local function mapsFor(proj, byGuid)
  local tl, em = {}, {}
  if not safe.projAlive(proj) then return tl, em end
  for i = 0, r.CountTracks(proj) - 1 do
    local t = r.GetTrack(proj, i)
    if t then
      local nm = safe.trackName(t)
      local key = byGuid and r.GetTrackGUID(t) or t
      tl[#tl + 1] = { key = key, name = nm }
      local k = norm(nm)
      if em[k] == nil then em[k] = key end
    end
  end
  return tl, em
end
local function findTarget(name, tl, em)
  local k = em[norm(name)]
  if k then return k, "exact" end
  local best, bestS = nil, 0
  for _, e in ipairs(tl) do
    local s = similarity(name, e.name)
    if s > bestS then bestS = s; best = e.key end
  end
  if best and bestS >= SIM_THRESHOLD then return best, "similar" end
  return nil, nil
end

--------------------------------------------------------------------------------
-- sends
--------------------------------------------------------------------------------
local SEND_PARAMS = { "D_VOL", "D_PAN", "B_MUTE", "B_MONO", "B_PHASE", "I_SENDMODE", "I_SRCCHAN", "I_DSTCHAN", "I_MIDIFLAGS" }
local function copySends(srcProj, srcTrack, dstProj, dstTrack, tl, em, dryRun)
  if not safe.trackAlive(srcProj, srcTrack) or not safe.trackAlive(dstProj, dstTrack) then return 0, 0, {} end
  local n = r.GetTrackNumSends(srcTrack, 0)
  local mapped, similar, missing = 0, 0, {}
  if not dryRun and n > 0 then   -- only clear when the source actually has sends
    for i = r.GetTrackNumSends(dstTrack, 0) - 1, 0, -1 do r.RemoveTrackSend(dstTrack, 0, i) end
  end
  local seen = {}   -- never create two sends to the same resolved target
  for i = 0, n - 1 do
    local dt = r.BR_GetMediaTrackSendInfo_Track(srcTrack, 0, i, 1)
    if dt and safe.trackAlive(srcProj, dt) then
      local target, kind = findTarget(safe.trackName(dt), tl, em)
      if target == dstTrack then target = nil end   -- a track never sends to itself
      if target and safe.trackAlive(dstProj, target) then
        if kind == "exact" then mapped = mapped + 1 else similar = similar + 1 end
        if not dryRun and not seen[target] then
          seen[target] = true
          local sidx = r.CreateTrackSend(dstTrack, target)
          -- -1 = REAPER refused (feedback loop); never write to index -1
          if sidx and sidx >= 0 then
            for _, p in ipairs(SEND_PARAMS) do
              r.SetTrackSendInfo_Value(dstTrack, 0, sidx, p, r.GetTrackSendInfo_Value(srcTrack, 0, i, p))
            end
          end
        end
      elseif not target then
        missing[#missing + 1] = safe.trackName(dt)
      end
    end
  end
  return mapped, similar, missing
end

--------------------------------------------------------------------------------
-- build a track into another project
--------------------------------------------------------------------------------
local function cloneTrackInto(srcProj, srcTrack, dstProj)
  if not safe.trackAlive(srcProj, srcTrack) or not safe.projAlive(dstProj) then return nil end
  local idx = r.CountTracks(dstProj)
  if r.InsertTrackInProject then
    r.InsertTrackInProject(dstProj, idx, 0)
  else
    local cur = r.EnumProjects(-1)
    r.SelectProjectInstance(dstProj)
    r.InsertTrackAtIndex(idx, false)
    if safe.projAlive(cur) then r.SelectProjectInstance(cur) end
  end
  local newTr = r.GetTrack(dstProj, idx)
  if not newTr then return nil end
  local ok, chunk = r.GetTrackStateChunk(srcTrack, "", false)
  if ok then r.SetTrackStateChunk(newTr, cleanChunkForBuild(chunk), false) end
  return newTr
end

--------------------------------------------------------------------------------
-- apply attributes to an existing matched track
--------------------------------------------------------------------------------
local function applyAttrs(srcProj, s, dstProj, d, attr, extras)
  if not safe.trackAlive(srcProj, s) or not safe.trackAlive(dstProj, d) then return end
  if attr.fx then
    local fx = getBlock(srcProj, s, FXCHAIN_PAT)
    if fx then setBlock(dstProj, d, FXCHAIN_PAT, stripParmEnv(fx)) end
  end
  if attr.vol then r.SetMediaTrackInfo_Value(d, "D_VOL", r.GetMediaTrackInfo_Value(s, "D_VOL")) end
  if attr.pan then
    r.SetMediaTrackInfo_Value(d, "D_PAN",     r.GetMediaTrackInfo_Value(s, "D_PAN"))
    r.SetMediaTrackInfo_Value(d, "D_WIDTH",   r.GetMediaTrackInfo_Value(s, "D_WIDTH"))
    r.SetMediaTrackInfo_Value(d, "I_PANMODE", r.GetMediaTrackInfo_Value(s, "I_PANMODE"))
  end
  if extras.color then r.SetMediaTrackInfo_Value(d, "I_CUSTOMCOLOR", r.GetMediaTrackInfo_Value(s, "I_CUSTOMCOLOR")) end
  if extras.inputfx then
    local rc = getBlock(srcProj, s, FXCHAIN_REC_PAT)
    if rc then setBlock(dstProj, d, FXCHAIN_REC_PAT, stripParmEnv(rc)) end
  end
end

--------------------------------------------------------------------------------
-- state   (NO MediaTrack* / ReaProject* is ever stored in a row - GUIDs only)
--------------------------------------------------------------------------------
local ctx = r.ImGui_CreateContext(APP)
ui.fonts(ctx)

local srcProj, focusTarget       -- ReaProject*, re-validated every poll before any use
local targetSel = {}             -- [proj] = true
local buildMode = false
local autoSync = true
local extras = { color = true, inputfx = false }
local tlist = {}                 -- focused To project: { {key=GUID, name=} } for the remap combos
local rows = {}                  -- { guid, name, tgtGuid, tgtName, kind, incl, userSet, attr }
local filter = ""
local lastSig = {}               -- { src=, tgt=, nproj=, t= }
local paint = {}                 -- drag-paint state for ui.tick
local confirmText = ""
local IDLE = "Tick the tracks to copy, check the amber guesses, Preview, then Transfer."

local function say(msg, level) ui.say(ctx, msg, level) end
local function pn(p) return safe.projName(p) end

local function otherProjects()
  local o = {}
  for _, p in ipairs(safe.openProjects()) do if p.proj ~= srcProj then o[#o + 1] = p end end
  return o
end
local function selectedTargets()
  local t = {}
  for _, p in ipairs(otherProjects()) do if targetSel[p.proj] then t[#t + 1] = p.proj end end
  return t
end
local function tickedRows()
  local n = 0
  for _, row in ipairs(rows) do if row.incl then n = n + 1 end end
  return n
end

--------------------------------------------------------------------------------
-- row building.  Rebuilds are lossless: every choice is carried across by
-- GUID, so an auto-refresh after you delete a track does not wipe your ticks
-- or manual remaps.  Guesses ("similar") start UNTICKED.
--------------------------------------------------------------------------------
local function buildRows(useSelection, keepChoices)
  local prev = {}
  if keepChoices then
    for _, row in ipairs(rows) do prev[row.guid] = row end
  end
  local tl, em = mapsFor(focusTarget, true)
  tlist = tl
  local tgtNames = {}
  for _, e in ipairs(tlist) do tgtNames[e.key] = e.name end

  local sel = safe.selectedGuids(srcProj)
  local anySel = next(sel) ~= nil
  rows = {}
  if not safe.projAlive(srcProj) then return end
  for i = 0, r.CountTracks(srcProj) - 1 do
    local t = r.GetTrack(srcProj, i)
    if t then
      local guid = r.GetTrackGUID(t)
      local nm = safe.trackName(t)
      local old = prev[guid]
      local tgtGuid, kind
      if old and old.userSet and old.tgtGuid and tgtNames[old.tgtGuid] then
        tgtGuid, kind = old.tgtGuid, old.kind
      elseif old and old.userSet and old.tgtGuid == nil then
        tgtGuid, kind = nil, "none"
      else
        tgtGuid, kind = findTarget(nm, tlist, em)
      end
      kind = kind or "none"
      local incl
      if old then incl = old.incl
      elseif kind == "similar" then incl = false            -- guesses are opt-in
      elseif useSelection and anySel then incl = (sel[guid] == true)
      else incl = true end
      rows[#rows + 1] = {
        guid = guid, name = nm,
        tgtGuid = tgtGuid, tgtName = tgtGuid and tgtNames[tgtGuid] or nil,
        kind = kind,
        incl = incl,
        userSet = old and old.userSet or false,
        attr = old and old.attr or { fx = true, vol = true, pan = true, sends = true },
      }
    end
  end
end

local function ensureFocus()
  for p in pairs(targetSel) do if not safe.projAlive(p) then targetSel[p] = nil end end
  local sels = selectedTargets()
  if #sels == 0 then focusTarget = nil; rows = {}; tlist = {}; return end
  local ok = false
  for _, p in ipairs(sels) do if p == focusTarget then ok = true end end
  if not ok then focusTarget = sels[1] end
  buildRows(true, true)
end

-- Smart pairing: sitting in a blank tab next to a full one means "build this
-- from that"; otherwise the fullest other project becomes the To.
local function autoPair()
  local active = r.EnumProjects(-1)
  if not safe.projAlive(srcProj) then srcProj = active end
  local other = densestOther(srcProj)
  if not other then return false end
  if r.CountTracks(srcProj) == 0 and r.CountTracks(other) > 0 then
    srcProj, other = other, srcProj
    buildMode = true
  end
  targetSel = {}; targetSel[other] = true; focusTarget = other
  return true
end

--------------------------------------------------------------------------------
-- the watcher.  Runs at the top of every frame, BEFORE anything reads a
-- pointer, so a track deleted since the last frame can never reach an API.
-- Uses safe.projSignature: it moves on add / delete / rename / reorder /
-- folder change (GetProjectStateChangeCount does not - measured).
--------------------------------------------------------------------------------
local function poll()
  local changed = false
  if srcProj and not safe.projAlive(srcProj) then
    local alt = densestOther(nil)
    srcProj = alt
    if alt then targetSel[alt] = nil end
    say(alt and ("The From project was closed - From is now " .. pn(alt) .. ".") or "The From project was closed.", "warn")
    changed = true
  end
  for p in pairs(targetSel) do
    if not safe.projAlive(p) then targetSel[p] = nil; changed = true; say("A To project was closed - dropped from the list.", "warn") end
  end
  if focusTarget and not safe.projAlive(focusTarget) then focusTarget = nil; changed = true end
  if not srcProj then rows, tlist = {}, {}; return end

  -- 4Hz is instant to a human and costs nothing on a big session
  local now = r.time_precise()
  if not changed and (now - (lastSig.t or 0)) < 0.25 then return end
  lastSig.t = now

  local nproj = #safe.openProjects()
  local sc = safe.projSignature(srcProj)
  local tc = focusTarget and safe.projSignature(focusTarget) or "none"
  if changed or sc ~= lastSig.src or tc ~= lastSig.tgt or nproj ~= lastSig.nproj then
    local hadProjects = lastSig.nproj or 0
    lastSig.src, lastSig.tgt, lastSig.nproj = sc, tc, nproj
    if nproj >= 2 and hadProjects < 2 and #selectedTargets() == 0 then
      if autoPair() then
        changed = true
        say(("Second tab found: %s -> %s."):format(pn(srcProj), pn(focusTarget)), "info")
      end
    end
    if autoSync or changed then
      ensureFocus()
      if focusTarget then buildRows(false, true) end
    end
  end
end

--------------------------------------------------------------------------------
-- plan  (what one To project would receive - never touches anything)
--   entry = { row=, tgtGuid=|nil, how="exact"|"guess"|"picked"|"new"|"none", clash= }
--   The focused project uses the row's target (guess ticks and remaps).  Any
--   other To project gets exact-name matches only: nobody has checked guesses
--   against it.
--------------------------------------------------------------------------------
local function planFor(dp)
  local plan = {}
  if not safe.projAlive(dp) then return plan end
  local isFocus = dp == focusTarget
  local dstAlive = safe.guidMap(dp)
  local _, em = mapsFor(dp, true)
  local usedBy = {}
  for _, row in ipairs(rows) do
    if row.incl then
      local e = { row = row }
      if isFocus then
        if row.tgtGuid and dstAlive[row.tgtGuid] then
          e.tgtGuid = row.tgtGuid
          e.how = row.kind == "similar" and "guess" or (row.kind == "manual" and "picked" or "exact")
        end
      else
        local k = em[norm(row.name)]
        if k then e.tgtGuid, e.how = k, "exact" end
      end
      if not e.tgtGuid then e.how = buildMode and "new" or "none" end
      if e.tgtGuid then
        local first = usedBy[e.tgtGuid]
        if first then e.clash = true; first.clash = true else usedBy[e.tgtGuid] = e end
      end
      plan[#plan + 1] = e
    end
  end
  return plan
end
local function planCounts(plan)
  local c = { exact = 0, guess = 0, picked = 0, new = 0, none = 0, clash = 0, touch = 0 }
  for _, e in ipairs(plan) do
    c[e.how] = (c[e.how] or 0) + 1
    if e.tgtGuid then c.touch = c.touch + 1 end
    if e.clash then c.clash = c.clash + 1 end
  end
  return c
end
local function planLine(dp, c)
  local bits = {}
  if c.exact > 0 then bits[#bits + 1] = c.exact .. " exact" end
  if c.picked > 0 then bits[#bits + 1] = c.picked .. " picked by you" end
  if c.guess > 0 then bits[#bits + 1] = c.guess .. (c.guess == 1 and " ticked guess" or " ticked guesses") end
  if c.new > 0 then bits[#bits + 1] = c.new .. " to build" end
  if c.none > 0 then bits[#bits + 1] = c.none .. " skipped (no match" .. (buildMode and ")" or ", Build is off)") end
  if c.clash > 0 then bits[#bits + 1] = c.clash .. " CLASH (two rows aim at one track)" end
  local line = pn(dp) .. ": " .. (#bits > 0 and table.concat(bits, ", ") or "nothing ticked")
  if dp ~= focusTarget then line = line .. " - exact names only; guesses are checked against the Compare-with project" end
  return line
end
-- First many-to-one problem across the To projects, as a sentence - or nil.
local function clashMessage(targets)
  for _, dp in ipairs(targets) do
    for _, e in ipairs(planFor(dp)) do
      if e.clash then
        return ("Two ticked rows point at the same track in %s (\"%s\"). Untick one of them, or give it a different target, then transfer."):format(
          pn(dp), e.row.tgtName or e.row.name)
      end
    end
  end
  return nil
end
local function transferSummary(targets)
  local parts, builds = {}, 0
  for _, dp in ipairs(targets) do
    local c = planCounts(planFor(dp))
    parts[#parts + 1] = ("%d track%s in %s"):format(c.touch, c.touch == 1 and "" or "s", pn(dp))
    builds = builds + c.new
  end
  local where
  if #parts <= 1 then where = parts[1] or "0 tracks"
  else where = table.concat(parts, ", ", 1, #parts - 1) .. " and " .. parts[#parts] end
  local text = "Replaces FX chains and sends on " .. where .. ". Existing sends on those tracks are removed first."
  if buildMode and builds > 0 then
    text = text .. (" Also builds %d new track%s."):format(builds, builds == 1 and "" or "s")
  end
  return text .. " Undo is available in each target project."
end

--------------------------------------------------------------------------------
-- preview / transfer
--------------------------------------------------------------------------------
local function doPreview()
  if not safe.projAlive(srcProj) then say("The From project has been closed.", "danger"); return end
  local targets = selectedTargets()
  if #targets == 0 then say("Tick at least one To project first.", "warn"); return end
  local prevActive = r.EnumProjects(-1)
  r.PreventUIRefresh(1)
  local ok, err = pcall(function()
    local lines, anyClash = {}, false
    for _, dp in ipairs(targets) do
      local c = planCounts(planFor(dp))
      if c.clash > 0 then anyClash = true end
      local line = planLine(dp, c)
      lines[#lines + 1] = line
      if #targets > 1 then say(line, c.clash > 0 and "danger" or "info") end
    end
    local head = anyClash and "Preview only, nothing changed - fix the clash before you transfer. " or "Preview only, nothing changed. "
    if #targets == 1 then say(head .. lines[1], anyClash and "warn" or "ok")
    else say(head .. #targets .. " projects checked - open the log for each one.", anyClash and "warn" or "ok") end
  end)
  local nowActive = r.EnumProjects(-1)
  if safe.projAlive(prevActive) and prevActive ~= nowActive then r.SelectProjectInstance(prevActive) end
  r.PreventUIRefresh(-1)
  if not ok then say("Preview stopped: " .. tostring(err), "danger") end
end

local function applyToTarget(dp, plan, counters)
  if not safe.projAlive(srcProj) or not safe.projAlive(dp) then return end
  local srcMap, dstMap = safe.guidMap(srcProj), safe.guidMap(dp)
  for _, e in ipairs(plan) do
    e.src = srcMap[e.row.guid]
    e.target = e.tgtGuid and dstMap[e.tgtGuid] or nil
    if not e.src then counters.vanished = counters.vanished + 1 end
  end
  if buildMode then
    for _, e in ipairs(plan) do
      if e.src and not e.target and e.how == "new" then
        e.target = cloneTrackInto(srcProj, e.src, dp)
        if e.target then e.created = true; counters.built = counters.built + 1 end
      end
    end
    counters.folderFixes = counters.folderFixes + safe.normaliseFolders(dp)
  end
  local tl, em = mapsFor(dp, false)   -- live pointers, this call only; includes built tracks
  for _, e in ipairs(plan) do
    if e.src and e.target and safe.trackAlive(dp, e.target) and safe.trackAlive(srcProj, e.src) then
      if not e.created then applyAttrs(srcProj, e.src, dp, e.target, e.row.attr, extras) end
      if e.row.attr.sends then
        r.SetMediaTrackInfo_Value(e.target, "B_MAINSEND", r.GetMediaTrackInfo_Value(e.src, "B_MAINSEND"))
        local _, _, missing = copySends(srcProj, e.src, dp, e.target, tl, em, false)
        for _, nm in ipairs(missing) do counters.missingSends[nm] = true end
      end
      counters.applied = counters.applied + 1
    end
  end
end

local function doTransfer()
  if not safe.projAlive(srcProj) then say("The From project has been closed.", "danger"); return end
  local targets = selectedTargets()
  if #targets == 0 then say("Tick at least one To project first.", "warn"); return end
  local clash = clashMessage(targets)
  if clash then say(clash, "danger"); return end

  local prevActive = r.EnumProjects(-1)
  local counters = { applied = 0, built = 0, vanished = 0, folderFixes = 0, missingSends = {} }
  local failed = 0
  r.PreventUIRefresh(1)
  if prevActive ~= srcProj then r.SelectProjectInstance(srcProj) end   -- SWS reads sends from the active project
  for _, dp in ipairs(targets) do
    if safe.projAlive(dp) then
      local plan = planFor(dp)
      r.Undo_BeginBlock2(dp)
      local ok, err = pcall(applyToTarget, dp, plan, counters)
      r.Undo_EndBlock2(dp, "Track Settings Transfer from " .. pn(srcProj), -1)
      r.MarkProjectDirty(dp)
      if ok then say(pn(dp) .. ": done.", "info")
      else failed = failed + 1; say(pn(dp) .. ": stopped - " .. tostring(err), "danger") end
    else
      say("A To project was closed during the transfer - skipped.", "warn")
    end
  end
  local nowActive = r.EnumProjects(-1)
  if safe.projAlive(prevActive) and prevActive ~= nowActive then r.SelectProjectInstance(prevActive) end
  r.PreventUIRefresh(-1)
  r.TrackList_AdjustWindows(false); r.UpdateArrange()

  local missing = {}
  for nm in pairs(counters.missingSends) do missing[#missing + 1] = nm end
  table.sort(missing)
  local msg = ("Transferred: %d track%s written, %d built, across %d project%s. Undo is in each of them."):format(
    counters.applied, counters.applied == 1 and "" or "s", counters.built, #targets, #targets == 1 and "" or "s")
  if counters.folderFixes > 0 then msg = msg .. (" %d folder end%s repaired."):format(counters.folderFixes, counters.folderFixes == 1 and "" or "s") end
  if counters.vanished > 0 then msg = msg .. (" %d From track%s vanished mid-way and were skipped."):format(counters.vanished, counters.vanished == 1 and "" or "s") end
  if #missing > 0 then msg = msg .. " Sends to these had no matching track and were left out: " .. table.concat(missing, ", ") .. "." end
  say(msg, failed > 0 and "warn" or "ok")
  lastSig.src, lastSig.tgt = nil, nil   -- force a refresh next frame
end

--------------------------------------------------------------------------------
-- small actions
--------------------------------------------------------------------------------
local function pickSource(p)
  -- A swap is a swap: when the project being promoted to From was a To, the
  -- outgoing From takes its place, so the list never empties out.
  local wasTarget = targetSel[p] == true
  local oldSrc = srcProj
  srcProj = p
  targetSel[p] = nil
  if wasTarget and oldSrc and oldSrc ~= p and safe.projAlive(oldSrc) then
    targetSel[oldSrc] = true; focusTarget = oldSrc
    say(("Swapped: now %s -> %s."):format(pn(p), pn(oldSrc)), "info")
  else
    say(("From is now %s."):format(pn(p)), "info")
  end
  if #selectedTargets() == 0 then
    local alt = densestOther(srcProj)
    if alt then targetSel[alt] = true; focusTarget = alt end
  end
  ensureFocus()
end

local function swapDirection()
  local newSrc = focusTarget
  if newSrc and safe.projAlive(newSrc) and newSrc ~= srcProj then
    local oldSrc = srcProj
    srcProj = newSrc
    targetSel = {}; targetSel[oldSrc] = true; focusTarget = oldSrc
    ensureFocus()
    say(("Swapped: now %s -> %s."):format(pn(srcProj), pn(oldSrc)), "info")
  else
    say("Nothing to swap with - tick a To project first.", "warn")
  end
end

local function refreshNow()
  lastSig.src, lastSig.tgt = nil, nil
  ensureFocus()
  if focusTarget then
    buildRows(false, true)
    say(("Refreshed: %d track%s in %s compared with %s."):format(#rows, #rows == 1 and "" or "s", pn(srcProj), pn(focusTarget)), "ok")
  else
    say("Refreshed. Tick a To project to see the track list.", "info")
  end
end

-- "Selected": tick only what is selected in the From project.  Remaps and
-- FX / Vol / Pan / Sends choices are kept - nothing is thrown away.
local function tickFromSelection()
  local sel = safe.selectedGuids(srcProj)
  if next(sel) == nil then
    say(("Nothing is selected in %s. Select the tracks you want there, then press Selected."):format(pn(srcProj)), "warn")
    return
  end
  local n, guessesOff = 0, 0
  for _, row in ipairs(rows) do
    if sel[row.guid] then
      if row.kind == "similar" then row.incl = false; guessesOff = guessesOff + 1
      else row.incl = true; n = n + 1 end
    else
      row.incl = false
    end
  end
  local msg = ("Ticked the %d selected track%s in %s; everything else off. Remaps and FX / Vol / Pan / Sends choices kept."):format(n, n == 1 and "" or "s", pn(srcProj))
  if guessesOff > 0 then
    msg = msg .. (" %d of the selected %s a guess (amber) and stayed off - check the target, then tick it."):format(guessesOff, guessesOff == 1 and "is" or "are")
  end
  say(msg, guessesOff > 0 and "warn" or "ok")
end

--------------------------------------------------------------------------------
-- table cells
--------------------------------------------------------------------------------
local function targetCombo(row)
  local noneLabel = buildMode and "(build new)" or "(none - skip)"
  r.ImGui_SetNextItemWidth(ctx, -1)
  if r.ImGui_BeginCombo(ctx, "##tgt", row.tgtName or noneLabel) then
    if r.ImGui_Selectable(ctx, noneLabel, row.tgtGuid == nil) then
      row.tgtGuid, row.tgtName, row.kind, row.userSet = nil, nil, "none", true
    end
    for _, e in ipairs(tlist) do
      r.ImGui_PushID(ctx, e.key)
      if r.ImGui_Selectable(ctx, e.name, e.key == row.tgtGuid) then
        row.tgtGuid, row.tgtName, row.userSet = e.key, e.name, true
        row.kind = (norm(e.name) == norm(row.name)) and "exact" or "manual"
      end
      r.ImGui_PopID(ctx)
    end
    r.ImGui_EndCombo(ctx)
  end
end

local function tagPill(row, clash)
  if clash then
    ui.pill(ctx, "clash", T.danger)
    ui.tip(ctx, "Another ticked row also points at this target track. Untick one of them, or give it a different target.")
  elseif row.kind == "exact" then
    ui.pill(ctx, "exact", T.ok)
    ui.tip(ctx, "Same name in both projects.")
  elseif row.kind == "similar" then
    ui.pill(ctx, "guess", T.warn)
    ui.tip(ctx, "A guess from a look-alike name. Check the target, then tick the row if it is right.")
  elseif row.kind == "manual" then
    ui.pill(ctx, "picked", T.ok)
    ui.tip(ctx, "You chose this target yourself.")
  elseif buildMode then
    ui.pill(ctx, "new", T.info)
    ui.tip(ctx, "No track with this name in the To project - it will be built there.")
  else
    ui.pill(ctx, "none", T.danger)
    ui.tip(ctx, "No track with this name in the To project. Skipped unless Build missing tracks is on, or you pick a target.")
  end
end

--------------------------------------------------------------------------------
-- frame
--------------------------------------------------------------------------------
local ATTRS = {
  { "FX",    "fx",    "Copy the FX chain. The target's own FX chain is replaced." },
  { "Vol",   "vol",   "Copy the fader level." },
  { "Pan",   "pan",   "Copy pan, width and pan mode." },
  { "Sends", "sends", "Rebuild the track's sends in the To project (matched by name). The target's existing sends are removed first." },
}

local setupOpen = nil   -- nil = decide from window height on first frame; then the user's choice

local function frame()
  poll()
  ui.header(ctx, APP, "import session data between tabs", function() ui.dockToggle(ctx) end, 70)

  local projects = safe.openProjects()
  if #projects < 2 then
    ui.empty(ctx, "Open a second project tab",
      "Open the other project in a new tab (File > New project tab) - it shows up here the moment it opens.")
    if ui.pushToBottom then ui.pushToBottom(ctx, 44) end
    ui.status(ctx, { idle = IDLE })
    return
  end
  if not safe.projAlive(srcProj) then srcProj = r.EnumProjects(-1) end

  local sels = selectedTargets()
  -- SETUP (from/to + what to copy) folds away so the track list gets the room,
  -- especially in the docker. Default: open when the window is tall, folded when
  -- it is short; your choice sticks for the session.
  if setupOpen == nil then setupOpen = (r.ImGui_GetWindowHeight(ctx) > 560) or (#sels == 0) end
  do
    local fromName = pn(srcProj)
    local toNames = {}
    for _, p in ipairs(sels) do toNames[#toNames + 1] = pn(p) end
    local what = {}
    for _, a in ipairs(ATTRS) do
      local any = false
      for _, row in ipairs(rows) do if row.incl and row.attr[a[2]] then any = true break end end
      if any then what[#what + 1] = a[1] end
    end
    if extras.color then what[#what + 1] = "Colour" end
    if extras.inputfx then what[#what + 1] = "Input FX" end
    local summary = ("From %s  >  To %s   |   %s%s"):format(fromName,
      #toNames > 0 and table.concat(toNames, ", ") or "(none)",
      #what > 0 and table.concat(what, " + ") or "nothing ticked",
      buildMode and "   |   builds missing tracks" or "")
    if ui.button(ctx, setupOpen and "Hide setup" or "Setup", { small = true, kind = setupOpen and "secondary" or "primary",
        tip = "Show or hide the From / To / what-to-copy controls so the track list gets the space." }) then
      setupOpen = not setupOpen
    end
    r.ImGui_SameLine(ctx, 0, 12)
    r.ImGui_AlignTextToFramePadding(ctx)
    ui.hint(ctx, summary)
  end
  if setupOpen then
    ------------------------------------------------------------------ from and to
    ui.section(ctx, "From and to")
    r.ImGui_AlignTextToFramePadding(ctx); ui.hint(ctx, "From"); r.ImGui_SameLine(ctx)
    local names, srcIdx = {}, 0
    for i, p in ipairs(projects) do names[i] = p.name; if p.proj == srcProj then srcIdx = i end end
    local fc, fidx = ui.combo(ctx, "##from", names, srcIdx, { w = 220, tip = "The project you are copying track settings FROM." })
    if fc and projects[fidx] and projects[fidx].proj ~= srcProj then pickSource(projects[fidx].proj) end
    r.ImGui_SameLine(ctx)
    if ui.button(ctx, "Swap", { small = true, tip = "Reverse the direction: the Compare-with project becomes From, and the current From becomes the To." }) then
      swapDirection()
    end
    r.ImGui_SameLine(ctx, 0, 18)
    local bc, bv = ui.toggle(ctx, "Build missing tracks", buildMode,
      "When a From track has no match in a To project, create it there: name, colour, FX, volume, pan, folder position - then rebuild its sends.")
    if bc then
      buildMode = bv
      say(bv and "Build is on: From tracks with no match will be created in the To project." or "Build is off: From tracks with no match are skipped.", "info")
    end
    r.ImGui_SameLine(ctx, 0, 18)
    local ac, av = ui.toggle(ctx, "Auto-sync", autoSync,
      "Watch both projects and refresh the list whenever a track is added, deleted, renamed, moved or refoldered. Your ticks and remaps are kept.")
    if ac then autoSync = av; if av then refreshNow() else say("Auto-sync is off. Press Refresh after you change tracks.", "info") end end
    r.ImGui_SameLine(ctx)
    ui.rightAlign(ctx, 76)
    if ui.button(ctx, "Refresh", { small = true, tip = "Re-read both projects and rebuild the list now. Ticks and remaps are kept." }) then refreshNow() end

    r.ImGui_AlignTextToFramePadding(ctx); ui.hint(ctx, "To")
    for _, p in ipairs(otherProjects()) do
      r.ImGui_SameLine(ctx)
      local on = targetSel[p.proj] == true
      -- plain checkbox (not ui.toggle) so the right-click is read before the tooltip
      local c, v = r.ImGui_Checkbox(ctx, p.name .. "##sel" .. tostring(p.proj), on)
      local rclick = r.ImGui_IsItemClicked and r.ImGui_IsItemClicked(ctx, 1)
      ui.tip(ctx, "Send settings to this project. The track list below is matched against the project under Compare with; other To projects get exact-name matches only. Right-click to compare with this one.")
      if c then
        targetSel[p.proj] = v or nil
        ensureFocus()
        say(v and ("Added " .. p.name .. " as a To project.") or ("Removed " .. p.name .. " from the To projects."), "info")
      end
      if rclick and targetSel[p.proj] and focusTarget ~= p.proj then
        focusTarget = p.proj; buildRows(true, true)
        say(("Now comparing %s with %s."):format(pn(srcProj), p.name), "info")
      end
    end
    r.ImGui_SameLine(ctx)
    if ui.button(ctx, "All", { small = true, tip = "Send to every other open project." }) then
      for _, p in ipairs(otherProjects()) do targetSel[p.proj] = true end
      ensureFocus()
      say(("Sending to all %d other project%s."):format(#selectedTargets(), #selectedTargets() == 1 and "" or "s"), "info")
    end
    r.ImGui_SameLine(ctx)
    if ui.button(ctx, "One", { small = true, tip = "Keep only the Compare-with project as the To." }) then
      if focusTarget and safe.projAlive(focusTarget) then
        targetSel = {}; targetSel[focusTarget] = true; ensureFocus()
        say("Sending only to " .. pn(focusTarget) .. ".", "info")
      else
        say("Tick a To project first.", "warn")
      end
    end

    if #sels > 0 then
      r.ImGui_AlignTextToFramePadding(ctx); ui.hint(ctx, "Compare with"); r.ImGui_SameLine(ctx)
      local items = {}
      for _, p in ipairs(sels) do
        items[#items + 1] = { id = p, label = pn(p) .. "##focus" .. tostring(p),
          tip = "Match the track list against this project. Guess ticks and remaps apply to it; the other To projects get exact-name matches only." }
      end
      local nf = ui.segmented(ctx, "focus", items, focusTarget)
      if nf ~= focusTarget then
        focusTarget = nf; buildRows(true, true)
        say(("Now comparing %s with %s."):format(pn(srcProj), pn(nf)), "info")
      end
      if #sels > 1 then r.ImGui_SameLine(ctx); ui.hint(ctx, "- the other To projects get exact-name matches only") end
    end

    ------------------------------------------------------------------ what to copy
    ui.section(ctx, "What to copy")
    r.ImGui_AlignTextToFramePadding(ctx); ui.hint(ctx, "Every row:")
    local function allAttr(k)
      local all, any = true, false
      for _, row in ipairs(rows) do if row.incl then any = true; if not row.attr[k] then all = false end end end
      return any and all
    end
    for _, a in ipairs(ATTRS) do
      r.ImGui_SameLine(ctx)
      local c, v = ui.toggle(ctx, a[1] .. "##all" .. a[2], allAttr(a[2]), a[3] .. " (sets every row)")
      if c then for _, row in ipairs(rows) do row.attr[a[2]] = v end end
    end
    r.ImGui_SameLine(ctx, 0, 18)
    local cc, cv = ui.toggle(ctx, "Colour", extras.color, "Copy the track colour onto matched tracks.")
    if cc then extras.color = cv end
    r.ImGui_SameLine(ctx)
    local ic, iv = ui.toggle(ctx, "Input FX", extras.inputfx, "Copy the input (record) FX chain onto matched tracks. The target's own input FX are replaced.")
    if ic then extras.inputfx = iv end
    ui.hint(ctx, "Automation is never copied.")


  end
  ------------------------------------------------------------------ tracks
  ui.section(ctx, "Tracks")
  local haveFocus = focusTarget ~= nil and safe.projAlive(focusTarget)
  local nT = #sels
  if not haveFocus then
    ui.empty(ctx, "Tick a project to send to",
      ("Tick one or more To projects above to match the tracks of %s against them by name."):format(pn(srcProj)))
    if ui.pushToBottom then ui.pushToBottom(ctx, 96) end
  else
    if ui.button(ctx, "Selected", { small = true, tip = "Tick only the tracks that are selected in the From project right now. Remaps and FX / Vol / Pan / Sends choices are kept." }) then
      tickFromSelection()
    end
    r.ImGui_SameLine(ctx)
    if ui.button(ctx, "Everything", { small = true, tip = "Tick every row - guesses included, so check their targets." }) then
      local g = 0
      for _, row in ipairs(rows) do row.incl = true; if row.kind == "similar" then g = g + 1 end end
      say(g > 0 and ("All %d rows ticked, including %d guess%s - check their targets before you transfer."):format(#rows, g, g == 1 and "" or "es")
                 or ("All %d rows ticked."):format(#rows), g > 0 and "warn" or "info")
    end
    r.ImGui_SameLine(ctx)
    if ui.button(ctx, "None", { small = true, tip = "Untick every row." }) then
      for _, row in ipairs(rows) do row.incl = false end
      say("All rows unticked.", "info")
    end
    r.ImGui_SameLine(ctx, 0, 14)
    r.ImGui_SetNextItemWidth(ctx, 170)
    local flc, flv = r.ImGui_InputTextWithHint(ctx, "##filter", "filter by name...", filter)
    if flc then filter = flv end
    ui.tip(ctx, "Show only tracks whose name contains this.")

    local nEx, nSim, nPick, nNone = 0, 0, 0, 0
    for _, row in ipairs(rows) do
      if row.kind == "exact" then nEx = nEx + 1
      elseif row.kind == "similar" then nSim = nSim + 1
      elseif row.kind == "manual" then nPick = nPick + 1
      elseif not row.tgtGuid then nNone = nNone + 1 end
    end
    r.ImGui_SameLine(ctx, 0, 14)
    r.ImGui_AlignTextToFramePadding(ctx)
    ui.text(ctx, nEx .. " exact", T.ok)
    r.ImGui_SameLine(ctx); ui.text(ctx, nSim .. (nSim == 1 and " guess" or " guesses"), T.warn)
    if nPick > 0 then r.ImGui_SameLine(ctx); ui.text(ctx, nPick .. " picked", T.ok) end
    r.ImGui_SameLine(ctx); ui.text(ctx, nNone .. (buildMode and " new" or " none"), buildMode and T.info or T.danger)
    ui.hint(ctx, "Amber rows are guesses - tick them yourself if they are right.")

    -- many-to-one, computed from the rows alone (cheap enough for every frame)
    local aimedAt = {}
    for _, row in ipairs(rows) do
      if row.incl and row.tgtGuid then aimedAt[row.tgtGuid] = (aimedAt[row.tgtGuid] or 0) + 1 end
    end

    if #rows == 0 then
      ui.empty(ctx, "No tracks in " .. pn(srcProj), "Press Swap if you meant to copy the other way.")
      if ui.pushToBottom then ui.pushToBottom(ctx, 96) end
    elseif ui.tableBegin(ctx, "tracks", {
        { name = "", w = 30 }, { name = "Source track" }, { name = "Target track" }, { name = "", w = 68 },
        { name = "FX", w = 36 }, { name = "Vol", w = 40 }, { name = "Pan", w = 40 }, { name = "Sends", w = 54 } },
        { reserve = 96 }) then
      local fn = norm(filter)
      for i, row in ipairs(rows) do
        if fn == "" or norm(row.name):find(fn, 1, true) then
          r.ImGui_TableNextRow(ctx); r.ImGui_PushID(ctx, i)
          r.ImGui_TableNextColumn(ctx)
          local c, v = ui.tick(ctx, "##i", row.incl, paint); if c then row.incl = v end
          r.ImGui_TableNextColumn(ctx)
          r.ImGui_AlignTextToFramePadding(ctx)
          local clash = row.incl and row.tgtGuid ~= nil and (aimedAt[row.tgtGuid] or 0) > 1
          ui.text(ctx, row.name, clash and T.danger or (row.incl and nil or T.muted))
          r.ImGui_TableNextColumn(ctx); targetCombo(row)
          r.ImGui_TableNextColumn(ctx); tagPill(row, clash)
          local dis = not row.incl
          for _, a in ipairs(ATTRS) do
            r.ImGui_TableNextColumn(ctx)
            if dis then r.ImGui_BeginDisabled(ctx, true) end
            local ac2, av2 = r.ImGui_Checkbox(ctx, "##" .. a[2], row.attr[a[2]])
            if ac2 then row.attr[a[2]] = av2 end
            if dis then r.ImGui_EndDisabled(ctx) end
          end
          r.ImGui_PopID(ctx)
        end
      end
      r.ImGui_EndTable(ctx)
    end
  end

  ------------------------------------------------------------------ actions
  local nTicked = tickedRows()
  if ui.button(ctx, "PREVIEW", { w = 140, h = 34, disabled = nT == 0,
      tip = "Dry run: says what would be matched, built and skipped in each To project. Changes nothing." }) then
    doPreview()
  end
  r.ImGui_SameLine(ctx, 0, 12)
  local label = nT == 1 and "TRANSFER TO 1 PROJECT" or ("TRANSFER TO %d PROJECTS"):format(nT)
  if ui.button(ctx, label, { kind = "primary", w = 260, h = 34, disabled = nT == 0 or nTicked == 0,
      tip = "Copies the ticked settings onto the To project(s). Asks first. One undo point per project." .. (buildMode and " Build is on: missing tracks are created." or "") }) then
    local clash = clashMessage(sels)
    if clash then say(clash, "danger")
    else confirmText = transferSummary(sels); ui.ask(ctx, "transfer") end
  end
  if nT > 0 and nTicked == 0 and haveFocus then
    r.ImGui_SameLine(ctx, 0, 12); r.ImGui_AlignTextToFramePadding(ctx); ui.hint(ctx, "Nothing ticked yet.")
  end

  if ui.confirm(ctx, "transfer", { title = "Transfer now?", text = confirmText, ok = "Transfer", danger = true }) then
    doTransfer()
  end

  ui.status(ctx, { idle = IDLE })
end

--------------------------------------------------------------------------------
-- init + loop
--------------------------------------------------------------------------------
srcProj = r.EnumProjects(-1)
if #safe.openProjects() >= 2 then
  autoPair()
  if focusTarget then buildRows(true, false) end
end

local function loop()
  local open = ui.window(ctx, { title = APP, accent = ui.accents.green, w = 940, h = 700, minW = 760, minH = 480 }, frame)
  if open then r.defer(loop) end
end
r.defer(loop)
