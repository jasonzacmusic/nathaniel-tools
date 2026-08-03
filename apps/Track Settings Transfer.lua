-- @description NPH Track Settings Transfer
-- @version 1.0.0
-- @author Jason Zac
-- @link https://daw.nathanielschool.com
-- @donation https://daw.nathanielschool.com/donate
-- @about Pro-Tools style Import Session Data across project tabs, both directions.
-- @changelog
--   1.0.0 - first public release. Crash-hardened (GUID identity + ValidatePtr2),
--           signature-based change detection, shared safety library.

--[[
  Track Settings Transfer  (v4)  -  REAPER / ReaImGui
  ------------------------------------------------------------------------------
  Pro-Tools "Import Session Data", supercharged and dockable.

  Works across ALL open projects (any number of tabs), two-way:
    * put any project on FROM (source) and any on TO (targets).
  Multi-target fan-out: tick several targets and transfer to all at once.

  MATCH mode: copy FX / Volume / Pan / Sends onto same-named tracks
    - exact name match, then similar-name match (flagged), plus manual remap.
    - per-track control of which attributes copy.

  BUILD mode: if a source track has no match in a target, CREATE it -
    name, color, FX, volume, pan, folder structure, then rebuild sends.

  Never copies automation. Preview changes nothing. One undo point per target.

  ----------------------------------------------------------------------------
  v4 - crash hardening.  REAPER frees MediaTrack* / ReaProject* the instant a
  track is deleted or a tab is closed.  Handing a freed pointer to any REAPER
  API faults inside REAPER's own C++, and Lua pcall CANNOT catch that: the host
  just dies.  v3 cached raw pointers in rows / tlist / exactMap / focusTarget,
  so deleting a track while the window was open was a guaranteed crash.

  v4 fixes that at the root:
    * The UI stores NO pointers.  Identity is r.GetTrackGUID(), which survives
      delete, undo, reorder and save/reload.  Pointers are resolved fresh,
      immediately before use, and never held across a frame.
    * Every project pointer passes r.ValidatePtr2(0, p, "ReaProject*") and
      every track pointer r.ValidatePtr2(proj, t, "MediaTrack*") before it
      touches an API.
    * GetProjectStateChangeCount() is polled each frame; when anything in the
      source or focus target changes, the row list rebuilds itself and keeps
      your per-track include / attribute / remap choices, keyed by GUID.
    * Closing a tab is handled: the app drops that target, re-picks a focus,
      and tells you in the log instead of dying.

  Also fixed in v4:
    * BUILD no longer leaves an unclosed folder.  I_FOLDERDEPTH is normalised
      after every build pass, so a cloned folder parent landing last can't
      swallow the rest of the target session.
    * copySends can no longer create a track -> itself send, and no longer
      writes send parameters to index -1 when REAPER refuses a feedback loop.
    * roleOf() walked pairs() - Lua hash order is non-deterministic, so the
      same track name could resolve to a different instrument family on
      different runs.  Family and token lookup are now ordered lists.
    * levenshtein is bounded (long names no longer stall the frame).
    * Drag-paint on the include column is contiguous: press and drag and every
      row between the anchor and the pointer flips; drag back and they restore.

  Requires: ReaImGui + SWS.
--]]

local r = reaper
local SIM_THRESHOLD = 0.55

if not r.ImGui_CreateContext then
  r.ShowMessageBox("Needs ReaImGui (Extensions > ReaPack > Browse packages > 'ReaImGui', install, restart).",
    "Track Settings Transfer", 0); return
end
if not r.BR_GetMediaTrackSendInfo_Track then
  r.ShowMessageBox("Needs the SWS extension (sws-extension.org).", "Track Settings Transfer", 0); return
end

--------------------------------------------------------------------------------
-- pointer safety  (the whole point of v4)
--------------------------------------------------------------------------------
local function projAlive(p)
  if p == nil then return false end
  local ok, alive = pcall(r.ValidatePtr2, 0, p, "ReaProject*")
  return ok and alive == true
end
local function trackAlive(proj, t)
  if t == nil or not projAlive(proj) then return false end
  local ok, alive = pcall(r.ValidatePtr2, proj, t, "MediaTrack*")
  return ok and alive == true
end
-- Change detection for the auto-sync watchdog.
--
-- This used to be GetProjectStateChangeCount.  MEASURED in REAPER 7.77: that
-- counter does NOT move when a track is inserted, renamed or deleted - it sat on
-- 8 through all three in a direct probe.  So the "Auto-sync" watchdog described
-- in the v4 header has in fact never fired, and the row list only ever refreshed
-- when something else happened to call ensureFocus().  That is why deleting a
-- track in the source project appeared to do nothing until you hit Rescan.
--
-- A cheap signature of the track list is the reliable substitute: it catches
-- add, delete, rename and reorder, which is exactly the set we care about.
local function stateCount(p)
  if not projAlive(p) then return -1 end
  local n = r.CountTracks(p)
  local acc = { n }
  for i = 0, n - 1 do
    local t = r.GetTrack(p, i)
    if t then
      local _, nm = r.GetSetMediaTrackInfo_String(t, "P_NAME", "", false)
      acc[#acc + 1] = r.GetTrackGUID(t) .. ":" .. (nm or "")
    end
  end
  return table.concat(acc, "|")
end

--------------------------------------------------------------------------------
-- string / similarity
--------------------------------------------------------------------------------
local function trim(s) return (s:gsub("^%s+",""):gsub("%s+$","")) end
local function norm(s) return trim((s or ""):lower():gsub("%s+"," ")) end
local function core(s)
  s = (s or ""):lower():gsub("[^%w]+"," ")
  local out = {}
  for tok in s:gmatch("%S+") do if not tok:match("^%d+$") and #tok > 1 then out[#out+1] = tok end end
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
      local del, ins, sub = prev[j] + 1, cur[j-1] + 1, prev[j-1] + cost
      local m = del < ins and del or ins
      cur[j] = m < sub and m or sub
    end
    for j = 0, #b do prev[j] = cur[j] end
  end
  return prev[#b]
end

-- instrument role synonyms: names in the same family are treated as related.
local ROLE_ALIASES = {
  acoustic = {"acoustic","aco","nylon","steel","folk"},
  drums    = {"drum","drums","kit","kick","snare","snr","hat","hihat","tom","floor","overhead","room","cymbal","ride","crash","perc","percussion","clap","shaker"},
  bass     = {"bass","808","sub"},
  guitar   = {"guitar","gtr","electric","elec","dist","distortion","drive","overdrive","crunch","heavy","riff","strat","tele","lespaul"},
  vocal    = {"vocal","vox","voice","bgv","harmony","choir","adlib"},
  keys     = {"keys","piano","pno","rhodes","wurli","wurlitzer","organ","clav","clavinet"},
  synth    = {"synth","pad","pads","poly","arp","pluck"},
  strings  = {"strings","violin","cello","viola","orchestra"},
  brass    = {"brass","horn","horns","trumpet","sax","trombone"},
  wind     = {"flute","whistle","melodica","clarinet","oboe","recorder"},
}
-- DETERMINISTIC resolution order.  "Acoustic" must win over "guitar" for a
-- track called "Acoustic Gtr", and it can only do that reliably if the walk
-- order is fixed.  pairs() does NOT give a fixed order in Lua.
local FAMILY_ORDER = { "acoustic","drums","bass","guitar","vocal","keys","synth","strings","brass","wind" }
-- short tokens that must match as whole words (avoid false hits inside longer words)
local ROLE_TOKENS = { ac="acoustic", ep="keys", od="guitar", gt="guitar", bs="bass" }
local TOKEN_ORDER = { "ac","ep","od","gt","bs" }

local function roleOf(name)
  local low = (name or ""):lower()
  local toks = {}
  for t in low:gmatch("%a+") do toks[t] = true end
  -- pass 1: exact short tokens, fixed order
  for _, tk in ipairs(TOKEN_ORDER) do if toks[tk] then return ROLE_TOKENS[tk] end end
  -- pass 2: whole-word family hits, fixed order
  for _, fam in ipairs(FAMILY_ORDER) do
    for _, w in ipairs(ROLE_ALIASES[fam]) do if toks[w] then return fam end end
  end
  -- pass 3: substring family hits (long words only), fixed order
  for _, fam in ipairs(FAMILY_ORDER) do
    for _, w in ipairs(ROLE_ALIASES[fam]) do
      if #w >= 4 and low:find(w, 1, true) then return fam end
    end
  end
  return nil
end

-- convention: a fully-UPPERCASE name is a bus / folder (not a track or a return)
local function isBusName(name)
  return name ~= "" and name == name:upper() and name:find("%u") ~= nil
end

local function similarity(a, b)
  local ca, cb = core(a), core(b)
  if ca == "" or cb == "" then ca, cb = norm(a), norm(b) end
  if ca == "" or cb == "" then return 0 end
  if ca == cb then return 1 end
  local contain = (ca:find(cb, 1, true) or cb:find(ca, 1, true)) and 0.85 or 0
  local jac = jaccard(tokenSet(ca), tokenSet(cb))
  local maxlen = math.max(#ca, #cb)
  local lev = maxlen > 0 and (1 - levenshtein(ca, cb) / maxlen) or 0
  local ra, rb = roleOf(a), roleOf(b)
  local roleBoost = (ra and rb and ra == rb) and 0.7 or 0
  if isBusName(a) ~= isBusName(b) then roleBoost = roleBoost * 0.5 end
  return math.max(contain, roleBoost, 0.5 * jac + 0.5 * lev)
end

--------------------------------------------------------------------------------
-- chunk helpers
--------------------------------------------------------------------------------
local function splitLines(chunk)
  local t = {}; for line in (chunk .. "\n"):gmatch("(.-)\n") do t[#t+1] = line end; return t
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
    else out[#out+1] = fx[i]; i = i + 1 end
  end
  return out
end
local function getBlock(proj, track, pat)
  if not trackAlive(proj, track) then return nil end
  local ok, chunk = r.GetTrackStateChunk(track, "", false)
  if not ok then return nil end
  local lines = splitLines(chunk)
  local s, e = findBlock(lines, pat)
  if not s then return nil end
  local b = {}; for i = s, e do b[#b+1] = lines[i] end; return b
end
local function setBlock(proj, track, pat, blk)
  if not trackAlive(proj, track) then return false end
  local ok, chunk = r.GetTrackStateChunk(track, "", false)
  if not ok then return false end
  local lines = splitLines(chunk)
  local s, e = findBlock(lines, pat)
  local out = {}
  if s then
    for i = 1, s - 1 do out[#out+1] = lines[i] end
    for _, l in ipairs(blk) do out[#out+1] = l end
    for i = e + 1, #lines do out[#out+1] = lines[i] end
  else
    local at
    for i = 1, #lines do if lines[i]:match("^%s*<ITEM") then at = i; break end end
    if not at then for i = #lines, 1, -1 do if lines[i]:match("^%s*>%s*$") then at = i; break end end end
    at = at or #lines
    for i = 1, at - 1 do out[#out+1] = lines[i] end
    for _, l in ipairs(blk) do out[#out+1] = l end
    for i = at, #lines do out[#out+1] = lines[i] end
  end
  return r.SetTrackStateChunk(track, table.concat(out, "\n"), false)
end
local FXCHAIN_PAT     = "^%s*<FXCHAIN%s*$"
local FXCHAIN_REC_PAT = "^%s*<FXCHAIN_REC"

-- for BUILD: keep name/color/fx/volpan/folder; drop items, automation, receives
local function cleanChunkForBuild(chunk)
  local lines = splitLines(chunk)
  local out, i = {}, 1
  while i <= #lines do
    local l = lines[i]
    if l:match("^%s*<ITEM") or l:match("^%s*<%u*ENV") then
      local e = findBlockEnd(lines, i); i = (e or i) + 1
    elseif l:match("^%s*AUXRECV") then
      i = i + 1
    else
      out[#out+1] = l; i = i + 1
    end
  end
  local s = table.concat(out, "\n")
  -- give the built track its own identity.  function form of gsub so a '%' can
  -- never appear in the replacement and blow up the pattern engine.
  s = s:gsub("TRACKID%s+{%x+%-%x+%-%x+%-%x+%-%x+}", function() return "TRACKID " .. r.genGuid("") end)
  return s
end

--------------------------------------------------------------------------------
-- projects / tracks
--------------------------------------------------------------------------------
local function trackName(t)
  local ok, nm = r.GetSetMediaTrackInfo_String(t, "P_NAME", "", false)
  if ok and nm ~= "" then return nm end
  return "Track " .. math.floor(r.GetMediaTrackInfo_Value(t, "IP_TRACKNUMBER"))
end
local function openProjects()
  local list, i = {}, 0
  while true do
    local p, path = r.EnumProjects(i)
    if not p then break end
    if projAlive(p) then
      local nm = (path or ""):match("[^/\\]+$") or ""
      nm = nm:gsub("%.[Rr][Pp][Pp]$", "")
      if nm == "" then nm = "(unsaved " .. (i + 1) .. ")" end
      list[#list+1] = { proj = p, name = nm, tracks = r.CountTracks(p) }
    end
    i = i + 1
  end
  return list
end
local function projName(proj)
  if not projAlive(proj) then return "(closed)" end
  for _, p in ipairs(openProjects()) do if p.proj == proj then return p.name end end
  return "(unknown)"
end
local function densestOther(exclude)
  local best, bestN = nil, -1
  for _, p in ipairs(openProjects()) do
    if p.proj ~= exclude and p.tracks > bestN then bestN = p.tracks; best = p.proj end
  end
  return best
end
-- guid -> live track, built fresh, never stored across a frame
local function guidMapOf(proj)
  local m = {}
  if not projAlive(proj) then return m end
  for i = 0, r.CountTracks(proj) - 1 do
    local t = r.GetTrack(proj, i)
    if t then m[r.GetTrackGUID(t)] = t end
  end
  return m
end

--------------------------------------------------------------------------------
-- matching
--   mapsFor(proj, byGuid): keys are GUIDs (safe to store) or live MediaTrack*
--   (only ever used inside the same call stack).  findTarget is key-agnostic.
--------------------------------------------------------------------------------
local function mapsFor(proj, byGuid)
  local tl, em = {}, {}
  if not projAlive(proj) then return tl, em end
  for i = 0, r.CountTracks(proj) - 1 do
    local t = r.GetTrack(proj, i)
    if t then
      local nm = trackName(t)
      local key = byGuid and r.GetTrackGUID(t) or t
      tl[#tl+1] = { key = key, name = nm }
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
local SEND_PARAMS = { "D_VOL","D_PAN","B_MUTE","B_MONO","B_PHASE","I_SENDMODE","I_SRCCHAN","I_DSTCHAN","I_MIDIFLAGS" }
local function copySends(srcProj, srcTrack, dstProj, dstTrack, tl, em, dryRun)
  if not trackAlive(srcProj, srcTrack) or not trackAlive(dstProj, dstTrack) then return 0, 0, {} end
  local n = r.GetTrackNumSends(srcTrack, 0)
  local mapped, similar, missing = 0, 0, {}
  if not dryRun and n > 0 then   -- only clear when the source actually has sends
    for i = r.GetTrackNumSends(dstTrack, 0) - 1, 0, -1 do r.RemoveTrackSend(dstTrack, 0, i) end
  end
  local seen = {}   -- de-dup: never create two sends to the same resolved target
  for i = 0, n - 1 do
    local dt = r.BR_GetMediaTrackSendInfo_Track(srcTrack, 0, i, 1)
    if dt and trackAlive(srcProj, dt) then
      local target, kind = findTarget(trackName(dt), tl, em)
      -- a track can never send to itself; that is what a folder/bus is for
      if target == dstTrack then target = nil end
      if target and trackAlive(dstProj, target) then
        if kind == "exact" then mapped = mapped + 1 else similar = similar + 1 end
        if not dryRun and not seen[target] then
          seen[target] = true
          local sidx = r.CreateTrackSend(dstTrack, target)
          -- CreateTrackSend returns -1 when REAPER refuses (feedback loop).
          -- v3 wrote parameters to index -1, which is undefined behaviour.
          if sidx and sidx >= 0 then
            for _, p in ipairs(SEND_PARAMS) do
              r.SetTrackSendInfo_Value(dstTrack, 0, sidx, p, r.GetTrackSendInfo_Value(srcTrack, 0, i, p))
            end
          end
        end
      elseif not target then
        missing[#missing+1] = trackName(dt)
      end
    end
  end
  return mapped, similar, missing
end

--------------------------------------------------------------------------------
-- folder depth repair
--   A cloned folder parent that lands last leaves I_FOLDERDEPTH open, and
--   REAPER then silently swallows every track after it into that folder - or
--   worse, the rest of the session.  Walk the list and make the arithmetic
--   well-formed: no depth > 1 step, no close deeper than we are, and the last
--   track always closes everything still open.
--------------------------------------------------------------------------------
local function normaliseFolders(proj)
  if not projAlive(proj) then return 0 end
  local n = r.CountTracks(proj); if n == 0 then return 0 end
  local depth, fixes = 0, 0
  for i = 0, n - 1 do
    local t = r.GetTrack(proj, i)
    if t then
      local fd = math.floor(r.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH") or 0)
      local want = fd
      if want > 1 then want = 1 end
      if i == n - 1 then
        want = -depth
      elseif want < 0 and -want > depth then
        want = -depth
      end
      if want ~= fd then r.SetMediaTrackInfo_Value(t, "I_FOLDERDEPTH", want); fixes = fixes + 1 end
      depth = depth + want
      if depth < 0 then depth = 0 end
    end
  end
  return fixes
end

--------------------------------------------------------------------------------
-- build a track into another project
--------------------------------------------------------------------------------
local function cloneTrackInto(srcProj, srcTrack, dstProj)
  if not trackAlive(srcProj, srcTrack) or not projAlive(dstProj) then return nil end
  local idx = r.CountTracks(dstProj)
  if r.InsertTrackInProject then
    r.InsertTrackInProject(dstProj, idx, 0)
  else
    local cur = r.EnumProjects(-1)
    r.SelectProjectInstance(dstProj)
    r.InsertTrackAtIndex(idx, false)
    if projAlive(cur) then r.SelectProjectInstance(cur) end
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
  if not trackAlive(srcProj, s) or not trackAlive(dstProj, d) then return end
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
-- state   (NO MediaTrack* / ReaProject* is ever stored in a row)
--------------------------------------------------------------------------------
local ctx = r.ImGui_CreateContext('Track Settings Transfer')
local srcProj, focusTarget
local targetSel = {}         -- [proj] = true   (validated every poll)
local buildMode = false
local extras = { color = true, inputfx = false }
local tlist = {}             -- focus target: { {key=GUID, name=...} }  display only
local rows = {}              -- { guid, name, tgtGuid, tgtName, kind, incl, attr, dead }
local filter = ""
local logLines = {}
local dockPending, firstFrame = nil, true
local autoSync = true
local lastCount = { src = -1, tgt = -1, nproj = -1 }
local paint = { active = false, val = false, anchorGuid = nil, base = {} }

local function log(s) logLines[#logLines+1] = s; if #logLines > 500 then table.remove(logLines, 1) end end

local function otherProjects()
  local o = {}
  for _, p in ipairs(openProjects()) do if p.proj ~= srcProj then o[#o+1] = p end end
  return o
end
local function selectedTargets()
  local t = {}
  for _, p in ipairs(otherProjects()) do if targetSel[p.proj] then t[#t+1] = p.proj end end
  return t
end
local function selectedGuids(proj)
  local s = {}
  if not projAlive(proj) then return s end
  for i = 0, r.CountSelectedTracks(proj) - 1 do
    local t = r.GetSelectedTrack(proj, i)
    if t then s[r.GetTrackGUID(t)] = true end
  end
  return s
end

--------------------------------------------------------------------------------
-- row building.  Rebuilds are cheap and lossless: every user choice is carried
-- across by GUID, so an auto-resync after you delete a track does not wipe
-- your include ticks or manual remaps.
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

  local sel = selectedGuids(srcProj)
  local anySel = next(sel) ~= nil
  rows = {}
  if not projAlive(srcProj) then return end
  for i = 0, r.CountTracks(srcProj) - 1 do
    local t = r.GetTrack(srcProj, i)
    if t then
      local guid = r.GetTrackGUID(t)
      local nm = trackName(t)
      local old = prev[guid]
      local tgtGuid, kind
      if old and old.userSet and old.tgtGuid and tgtNames[old.tgtGuid] then
        tgtGuid, kind = old.tgtGuid, old.kind
      elseif old and old.userSet and old.tgtGuid == nil then
        tgtGuid, kind = nil, "none"
      else
        tgtGuid, kind = findTarget(nm, tlist, em)
      end
      local incl
      if old then incl = old.incl
      elseif useSelection and anySel then incl = (sel[guid] == true)
      else incl = true end
      rows[#rows+1] = {
        guid = guid, name = nm,
        tgtGuid = tgtGuid, tgtName = tgtGuid and tgtNames[tgtGuid] or nil,
        kind = kind or "none",
        incl = incl,
        userSet = old and old.userSet or false,
        attr = old and old.attr or { fx = true, vol = true, pan = true, sends = true },
      }
    end
  end
end

local function ensureFocus()
  -- drop any target project that has been closed
  for p in pairs(targetSel) do if not projAlive(p) then targetSel[p] = nil end end
  local sels = selectedTargets()
  if #sels == 0 then focusTarget = nil; rows = {}; tlist = {}; return end
  local ok = false
  for _, p in ipairs(sels) do if p == focusTarget then ok = true end end
  if not ok then focusTarget = sels[1] end
  buildRows(true, true)
end

--------------------------------------------------------------------------------
-- the watchdog.  Runs at the top of every frame, BEFORE anything reads a
-- pointer, so a track deleted since the last frame can never reach an API.
--------------------------------------------------------------------------------
local function pollForChanges()
  local changed = false

  if not projAlive(srcProj) then
    local alt = densestOther(nil)
    log("Source project closed" .. (alt and (" - switched to " .. projName(alt)) or ""))
    srcProj = alt
    if srcProj then targetSel[srcProj] = nil end
    changed = true
  end
  for p in pairs(targetSel) do
    if not projAlive(p) then targetSel[p] = nil; changed = true; log("A target project was closed - dropped.") end
  end
  if focusTarget and not projAlive(focusTarget) then focusTarget = nil; changed = true end
  if not srcProj then rows = {}; tlist = {}; return end

  -- Throttle: the signature walks every track in both projects, and this runs on
  -- the UI thread.  4Hz is instant to a human and costs nothing on a big session.
  local now = r.time_precise()
  if not changed and (now - (lastCount.t or 0)) < 0.25 then return end
  lastCount.t = now

  local nproj = #openProjects()
  local sc = stateCount(srcProj)
  local tc = stateCount(focusTarget)
  if changed or sc ~= lastCount.src or tc ~= lastCount.tgt or nproj ~= lastCount.nproj then
    lastCount.src, lastCount.tgt, lastCount.nproj = sc, tc, nproj
    if autoSync or changed then
      ensureFocus()
      if focusTarget then buildRows(false, true) end
    end
  end
end

--------------------------------------------------------------------------------
-- preview / transfer
--------------------------------------------------------------------------------
local function doPreview()
  logLines = {}
  local targets = selectedTargets()
  if #targets == 0 then log("Pick at least one target project."); return end
  if not projAlive(srcProj) then log("Source project is gone."); return end
  local prevActive = r.EnumProjects(-1)
  if prevActive ~= srcProj then r.SelectProjectInstance(srcProj) end
  log(("PREVIEW  source '%s'  ->  %d target(s)%s"):format(projName(srcProj), #targets, buildMode and "   [BUILD ON]" or ""))
  for _, dp in ipairs(targets) do
    if projAlive(dp) then
      local tl, em = mapsFor(dp, false)
      local m, c, s = 0, 0, 0
      for _, row in ipairs(rows) do
        if row.incl then
          local hit
          if dp == focusTarget then hit = row.tgtGuid ~= nil
          else hit = (findTarget(row.name, tl, em)) ~= nil end
          if hit then m = m + 1 elseif buildMode then c = c + 1 else s = s + 1 end
        end
      end
      log(("  %-22s  %d match, %d %s, %d skipped"):format(projName(dp), m, buildMode and c or 0,
        buildMode and "to BUILD" or "unmatched(off)", buildMode and s or (c + s)))
    end
  end
  if projAlive(prevActive) and prevActive ~= srcProj then r.SelectProjectInstance(prevActive) end
  log("--- preview only, nothing changed ---")
end

local function applyToTarget(dp, isFocus, counters)
  if not projAlive(srcProj) or not projAlive(dp) then return end
  local srcByGuid = guidMapOf(srcProj)
  local dstByGuid = guidMapOf(dp)
  local tl, em = mapsFor(dp, false)

  local plan = {}
  for _, row in ipairs(rows) do
    if row.incl then
      local st = srcByGuid[row.guid]
      if st and trackAlive(srcProj, st) then
        local tgt
        if isFocus then
          tgt = row.tgtGuid and dstByGuid[row.tgtGuid] or nil
        else
          tgt = (findTarget(row.name, tl, em))
        end
        if tgt and not trackAlive(dp, tgt) then tgt = nil end
        plan[#plan+1] = { row = row, src = st, target = tgt }
      else
        counters.skipped = counters.skipped + 1
      end
    end
  end

  if buildMode then
    for _, p in ipairs(plan) do
      if not p.target then
        p.target = cloneTrackInto(srcProj, p.src, dp)
        if p.target then p.created = true; counters.built = counters.built + 1 end
      end
    end
    counters.folderFixes = counters.folderFixes + normaliseFolders(dp)
    tl, em = mapsFor(dp, false) -- include new tracks as send destinations
  end

  for _, p in ipairs(plan) do
    if p.target and trackAlive(dp, p.target) and trackAlive(srcProj, p.src) then
      if not p.created then applyAttrs(srcProj, p.src, dp, p.target, p.row.attr, extras) end
      if p.row.attr.sends then
        r.SetMediaTrackInfo_Value(p.target, "B_MAINSEND", r.GetMediaTrackInfo_Value(p.src, "B_MAINSEND"))
        copySends(srcProj, p.src, dp, p.target, tl, em, false)
      end
      counters.applied = counters.applied + 1
    end
  end
end

local function doTransfer()
  logLines = {}
  if not projAlive(srcProj) then log("Source project is gone."); return end
  local targets = selectedTargets()
  if #targets == 0 then log("Pick at least one target project."); return end
  local prevActive = r.EnumProjects(-1)
  local counters = { applied = 0, built = 0, skipped = 0, folderFixes = 0 }
  if prevActive ~= srcProj then r.SelectProjectInstance(srcProj) end  -- SWS send reads need source active
  for _, dp in ipairs(targets) do
    if projAlive(dp) then
      r.Undo_BeginBlock2(dp); r.PreventUIRefresh(1)
      local ok, err = pcall(applyToTarget, dp, dp == focusTarget, counters)
      r.PreventUIRefresh(-1)
      r.Undo_EndBlock2(dp, "Track Settings Transfer from " .. projName(srcProj), -1)
      r.MarkProjectDirty(dp)
      log("  " .. projName(dp) .. (ok and ": done" or (": ERROR " .. tostring(err))))
    else
      log("  (a target closed mid-transfer - skipped)")
    end
  end
  if projAlive(prevActive) and prevActive ~= srcProj then r.SelectProjectInstance(prevActive) end
  r.TrackList_AdjustWindows(false); r.UpdateArrange()
  log(("Finished. %d track-ops, %d built, %d folder depths repaired, %d source tracks vanished, across %d project(s). Undo per project."):format(
    counters.applied, counters.built, counters.folderFixes, counters.skipped, #targets))
  lastCount.src, lastCount.tgt = -1, -1   -- force a resync next frame
end

--------------------------------------------------------------------------------
-- init (smart launch)
--------------------------------------------------------------------------------
local active = r.EnumProjects(-1)
if #openProjects() < 2 then
  r.ShowMessageBox("Open at least two projects (tabs) so there's a source and a target.", "Track Settings Transfer", 0)
  return
end
if r.CountTracks(active) == 0 then
  srcProj = densestOther(active)   -- blank active -> build it from densest other
  focusTarget = active
  targetSel[active] = true
  buildMode = true
else
  srcProj = active
  focusTarget = densestOther(srcProj)
  targetSel[focusTarget] = true
end
buildRows(true, false)

--------------------------------------------------------------------------------
-- colors / ui
--------------------------------------------------------------------------------
local COL_EXACT, COL_SIMILAR, COL_NONE, COL_MUTED = 0x54D07AFF, 0xE8B23AFF, 0xE06A5AFF, 0x8892A0FF
local COL_DEAD = 0xE0455AFF

local function projectCombo(id, current, onPick)
  r.ImGui_SetNextItemWidth(ctx, 170)
  if r.ImGui_BeginCombo(ctx, id, projName(current)) then
    for _, p in ipairs(openProjects()) do
      if r.ImGui_Selectable(ctx, p.name .. "##" .. tostring(p.proj), p.proj == current) then onPick(p.proj) end
    end
    r.ImGui_EndCombo(ctx)
  end
end

local function targetCombo(row, idx)
  local preview = row.tgtName or "-- none (build) --"
  local col = row.tgtGuid and (row.kind == "similar" and COL_SIMILAR or COL_EXACT) or COL_NONE
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), col)
  r.ImGui_SetNextItemWidth(ctx, -1)
  local opened = r.ImGui_BeginCombo(ctx, "##tgt" .. idx, preview)
  r.ImGui_PopStyleColor(ctx, 1)
  if opened then
    if r.ImGui_Selectable(ctx, "-- none (build) --", row.tgtGuid == nil) then
      row.tgtGuid = nil; row.tgtName = nil; row.kind = "none"; row.userSet = true
    end
    for _, e in ipairs(tlist) do
      if r.ImGui_Selectable(ctx, e.name .. "##t" .. idx .. e.key, e.key == row.tgtGuid) then
        row.tgtGuid = e.key; row.tgtName = e.name; row.userSet = true
        row.kind = (norm(e.name) == norm(row.name)) and "exact" or "manual"
      end
    end
    r.ImGui_EndCombo(ctx)
  end
end

--------------------------------------------------------------------------------
-- contiguous drag paint of the include column
--   press on a checkbox and drag: every row between the anchor and the pointer
--   takes the anchor's new value; drag back and the ones you left restore.
--------------------------------------------------------------------------------
local function paintApply(band)
  if not paint.active or not paint.anchorGuid or #band == 0 then return end
  local _, my = r.ImGui_GetMousePos(ctx)
  local ai, ci
  for i, b in ipairs(band) do
    if b.row.guid == paint.anchorGuid then ai = i end
    if my >= b.y1 and my <= b.y2 then ci = i end
  end
  if not ai then return end
  if not ci then
    if my < band[1].y1 then ci = 1
    elseif my > band[#band].y2 then ci = #band
    else ci = ai end
  end
  local lo, hi = math.min(ai, ci), math.max(ai, ci)
  for i, b in ipairs(band) do
    if i >= lo and i <= hi then b.row.incl = paint.val
    else
      local base = paint.base[b.row.guid]
      if base ~= nil then b.row.incl = base end
    end
  end
end

local function frame()
  pollForChanges()

  if not r.ImGui_IsMouseDown(ctx, 0) then
    paint.active = false; paint.anchorGuid = nil
  end

  -- row 1: source + build + dock
  r.ImGui_AlignTextToFramePadding(ctx); r.ImGui_Text(ctx, "From")
  r.ImGui_SameLine(ctx)
  projectCombo("##from", srcProj, function(p)
    -- DIRECTION FIX.  Reported symptom: "choosing one session and importing from
    -- another doesn't work, while the other way round works."
    --
    -- Cause: picking a new source removed that project from the target list
    -- (correct - nothing may be its own target) but nothing ever took its place.
    -- Swapping A->B into B->A therefore left ZERO targets selected, ensureFocus()
    -- cleared focusTarget, and the whole track list vanished behind
    -- "Select a target project above."  The app looked broken in one direction
    -- and fine in the other, which is exactly what was described.
    --
    -- Fix: a swap is a swap.  When the project being promoted to source was a
    -- target, the outgoing source inherits its place, so From/To simply trade
    -- ends and the list stays populated.
    local wasTarget = targetSel[p] == true
    local oldSrc    = srcProj
    srcProj = p
    targetSel[p] = nil
    if wasTarget and oldSrc and oldSrc ~= p and projAlive(oldSrc) then
      targetSel[oldSrc] = true
      focusTarget = oldSrc
      log(("Swapped direction: now '%s'  ->  '%s'"):format(projName(p), projName(oldSrc)))
    end
    -- Belt and braces: never leave the user with no target at all when there is
    -- an obvious one to pick.
    if #selectedTargets() == 0 then
      local alt = densestOther(srcProj)
      if alt then targetSel[alt] = true; focusTarget = alt end
    end
    ensureFocus()
  end)
  -- One-click direction reversal.  Import INTO the session you are sitting in,
  -- or OUT of it, without hunting through two separate controls.
  r.ImGui_SameLine(ctx)
  if r.ImGui_SmallButton(ctx, "<-> Swap") then
    local newSrc = focusTarget
    if newSrc and projAlive(newSrc) and newSrc ~= srcProj then
      local oldSrc = srcProj
      srcProj = newSrc
      targetSel = {}
      targetSel[oldSrc] = true
      focusTarget = oldSrc
      log(("Swapped direction: now '%s'  ->  '%s'"):format(projName(srcProj), projName(oldSrc)))
      ensureFocus()
    else
      log("Nothing to swap with - tick a target project first.")
    end
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Reverse the direction: the focused target becomes the source\nand the current source becomes the target.")
  end

  r.ImGui_SameLine(ctx)
  local bchg, bval = r.ImGui_Checkbox(ctx, "Build missing tracks", buildMode)
  if bchg then buildMode = bval end
  r.ImGui_SameLine(ctx)
  local achg, aval = r.ImGui_Checkbox(ctx, "Auto-sync", autoSync)
  if achg then autoSync = aval end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Watch both projects and rebuild the list whenever you add, delete,\nrename or reorder a track. Your ticks and remaps are kept.")
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_SmallButton(ctx, "Rescan") then lastCount.src, lastCount.tgt = -1, -1; ensureFocus() end
  r.ImGui_SameLine(ctx)
  local docked = r.ImGui_IsWindowDocked(ctx)
  local dchg, dval = r.ImGui_Checkbox(ctx, "Dock", docked)
  if dchg then dockPending = dval and -1 or 0 end

  -- row 2: targets (multi-select)
  r.ImGui_AlignTextToFramePadding(ctx); r.ImGui_Text(ctx, "To")
  for _, p in ipairs(otherProjects()) do
    r.ImGui_SameLine(ctx)
    local on = targetSel[p.proj] == true
    local isFocus = p.proj == focusTarget
    if isFocus then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COL_EXACT) end
    local c, v = r.ImGui_Checkbox(ctx, p.name .. "##sel" .. tostring(p.proj), on)
    if isFocus then r.ImGui_PopStyleColor(ctx, 1) end
    if c then targetSel[p.proj] = v or nil; ensureFocus() end
    if r.ImGui_IsItemClicked and r.ImGui_IsItemClicked(ctx, 1) then focusTarget = p.proj; buildRows(true, true) end
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_SmallButton(ctx, "All") then for _, p in ipairs(otherProjects()) do targetSel[p.proj] = true end ensureFocus() end
  r.ImGui_SameLine(ctx)
  if r.ImGui_SmallButton(ctx, "One") then targetSel = {}; if focusTarget then targetSel[focusTarget] = true end ensureFocus() end

  r.ImGui_Separator(ctx)

  if not focusTarget or not projAlive(focusTarget) then
    r.ImGui_TextColored(ctx, COL_NONE, "Select a target project above.")
    return
  end

  -- row 3: selection + filter + counts
  if r.ImGui_Button(ctx, "Selected") then buildRows(true, false) end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Everything") then for _, row in ipairs(rows) do row.incl = true end end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "None") then for _, row in ipairs(rows) do row.incl = false end end
  r.ImGui_SameLine(ctx)
  r.ImGui_SetNextItemWidth(ctx, 150)
  local fc, fv = r.ImGui_InputTextWithHint(ctx, "##filter", "filter...", filter)
  if fc then filter = fv end
  r.ImGui_SameLine(ctx)
  local nEx, nSim, nNone = 0, 0, 0
  for _, row in ipairs(rows) do
    if row.kind == "exact" then nEx = nEx + 1 elseif row.kind == "similar" then nSim = nSim + 1
    elseif not row.tgtGuid then nNone = nNone + 1 end
  end
  r.ImGui_TextColored(ctx, COL_MUTED, "vs " .. projName(focusTarget) .. ":")
  r.ImGui_SameLine(ctx); r.ImGui_TextColored(ctx, COL_EXACT, nEx .. " exact")
  r.ImGui_SameLine(ctx); r.ImGui_TextColored(ctx, COL_SIMILAR, nSim .. " similar")
  r.ImGui_SameLine(ctx); r.ImGui_TextColored(ctx, COL_NONE, nNone .. (buildMode and " to build" or " none"))

  -- apply-to-all
  r.ImGui_AlignTextToFramePadding(ctx); r.ImGui_TextColored(ctx, COL_MUTED, "Apply to all:")
  local function allAttr(k) local all, any = true, false
    for _, row in ipairs(rows) do if row.incl then any = true; if not row.attr[k] then all = false end end end
    return any and all end
  for _, kv in ipairs({ {"FX","fx"}, {"Vol","vol"}, {"Pan","pan"}, {"Sends","sends"} }) do
    r.ImGui_SameLine(ctx)
    local c, v = r.ImGui_Checkbox(ctx, kv[1] .. "##all" .. kv[2], allAttr(kv[2]))
    if c then for _, row in ipairs(rows) do row.attr[kv[2]] = v end end
  end

  -- table
  local band = {}
  local tflags = r.ImGui_TableFlags_Borders() | r.ImGui_TableFlags_RowBg()
    | r.ImGui_TableFlags_ScrollY() | r.ImGui_TableFlags_SizingStretchProp()
  local _, availH = r.ImGui_GetContentRegionAvail(ctx)
  if r.ImGui_BeginTable(ctx, "tt", 7, tflags, 0, math.max(120, availH - 120)) then
    r.ImGui_TableSetupScrollFreeze(ctx, 0, 1)
    r.ImGui_TableSetupColumn(ctx, "##i", r.ImGui_TableColumnFlags_WidthFixed(), 24)
    r.ImGui_TableSetupColumn(ctx, "Source track", r.ImGui_TableColumnFlags_WidthStretch())
    r.ImGui_TableSetupColumn(ctx, "Target track", r.ImGui_TableColumnFlags_WidthStretch())
    r.ImGui_TableSetupColumn(ctx, "FX", r.ImGui_TableColumnFlags_WidthFixed(), 32)
    r.ImGui_TableSetupColumn(ctx, "Vol", r.ImGui_TableColumnFlags_WidthFixed(), 34)
    r.ImGui_TableSetupColumn(ctx, "Pan", r.ImGui_TableColumnFlags_WidthFixed(), 34)
    r.ImGui_TableSetupColumn(ctx, "Sends", r.ImGui_TableColumnFlags_WidthFixed(), 42)
    r.ImGui_TableHeadersRow(ctx)
    local fn = norm(filter)
    for i, row in ipairs(rows) do
      if fn == "" or norm(row.name):find(fn, 1, true) then
        r.ImGui_TableNextRow(ctx); r.ImGui_PushID(ctx, i)
        r.ImGui_TableNextColumn(ctx)
        local ic, iv = r.ImGui_Checkbox(ctx, "##i", row.incl)
        local x1, y1 = r.ImGui_GetItemRectMin(ctx)
        local x2, y2 = r.ImGui_GetItemRectMax(ctx)
        band[#band+1] = { y1 = y1, y2 = y2, row = row }
        if ic then
          row.incl = iv
          paint.active = true; paint.val = iv; paint.anchorGuid = row.guid
          paint.base = {}
          for _, rr in ipairs(rows) do paint.base[rr.guid] = rr.incl end
          paint.base[row.guid] = iv
        end
        r.ImGui_TableNextColumn(ctx)
        local tag = row.kind == "exact" and "=" or (row.kind == "similar" and "~" or (row.tgtGuid and "*" or "+"))
        local tc = row.kind == "exact" and COL_EXACT or (row.kind == "similar" and COL_SIMILAR or (row.tgtGuid and COL_EXACT or COL_NONE))
        r.ImGui_TextColored(ctx, tc, tag); r.ImGui_SameLine(ctx)
        if row.incl then r.ImGui_Text(ctx, row.name) else r.ImGui_TextColored(ctx, COL_MUTED, row.name) end
        r.ImGui_TableNextColumn(ctx); targetCombo(row, i)
        local dis = not row.incl
        for _, kv in ipairs({ {"##fx","fx"}, {"##v","vol"}, {"##p","pan"}, {"##s","sends"} }) do
          r.ImGui_TableNextColumn(ctx)
          if dis then r.ImGui_BeginDisabled(ctx) end
          local cc, cv = r.ImGui_Checkbox(ctx, kv[1], row.attr[kv[2]]); if cc then row.attr[kv[2]] = cv end
          if dis then r.ImGui_EndDisabled(ctx) end
        end
        r.ImGui_PopID(ctx)
      end
    end
    r.ImGui_EndTable(ctx)
  end
  paintApply(band)

  -- extras + actions
  local ec, ev = r.ImGui_Checkbox(ctx, "Color", extras.color); if ec then extras.color = ev end
  r.ImGui_SameLine(ctx)
  local i2, v2 = r.ImGui_Checkbox(ctx, "Input FX", extras.inputfx); if i2 then extras.inputfx = v2 end
  r.ImGui_SameLine(ctx); r.ImGui_TextColored(ctx, COL_MUTED, "  Automation never copied.")
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Preview") then doPreview() end
  r.ImGui_SameLine(ctx)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x2E7D46FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x379B55FF)
  local nT = #selectedTargets()
  local go = r.ImGui_Button(ctx, (buildMode and "BUILD / TRANSFER" or "TRANSFER") .. " -> " .. nT .. " proj")
  r.ImGui_PopStyleColor(ctx, 2)
  if go then doTransfer() end

  local cb = r.ImGui_ChildFlags_Border and r.ImGui_ChildFlags_Border() or 0
  if r.ImGui_BeginChild(ctx, "log", 0, 0, cb) then
    for _, l in ipairs(logLines) do r.ImGui_Text(ctx, l) end
    r.ImGui_EndChild(ctx)
  end
end

local function loop()
  if dockPending ~= nil then r.ImGui_SetNextWindowDockID(ctx, dockPending); dockPending = nil end
  if firstFrame then r.ImGui_SetNextWindowSize(ctx, 860, 660); firstFrame = false end
  local visible, open = r.ImGui_Begin(ctx, 'Track Settings Transfer', true)
  if visible then
    local ok, err = pcall(frame)
    if not ok then r.ImGui_TextColored(ctx, COL_DEAD, "Error: " .. tostring(err)) end
    r.ImGui_End(ctx)
  end
  if open then r.defer(loop) end
end
r.defer(loop)
