-- @description NPH StageRig
-- @version 0.1.0
-- @author Jason Zac
-- @link https://daw.nathanielschool.com
-- @donation https://daw.nathanielschool.com/donate
-- @about
--   Live patch switching for REAPER. Reads a setlist built by StageRig Build,
--   shows a stage view with CURRENT and NEXT, and switches patches without
--   cutting off what is still ringing.
-- @changelog
--   0.1.0 - first version. Switching, panic, stage view.

--[[
  NPH: StageRig  (violet - performance)
  ----------------------------------------------------------------------------
  THE SWITCH, in the order that matters (NPH_TECH_BRIEF §7):

    1. unmute the INCOMING patch first, so it is already playable
    2. close the gate on the OUTGOING patch, so no new notes reach it while
       what is already sounding continues
    3. let it ring (default 2.0 s, adjustable)
    4. flush: matching note-offs + CC64=0, then mute

  Doing it in any other order produces the two failures every naive switcher
  has: a chopped-off chord (mute first) or a stuck note (mute without flushing).

  WHAT THIS SCRIPT IS NOT ALLOWED TO DO
  It does not touch the note path. reaper.defer runs at UI cadence, ~15-30 ms,
  and is not sample-accurate; note handling there is audibly wrong and racy.
  Notes are handled by nph_note_tracker.jsfx at audio rate. This script only
  decides WHEN, and sets parameters.

  Nothing is created, destroyed or reconfigured during a set. Every instrument
  was instantiated by StageRig Build. Switching is mute and gate only.

  Pointer discipline: tracks are held as GUIDs and resolved per frame. A track
  deleted behind the app's back becomes a reported gap, never a crash.
--]]

local r = reaper

do
  local sep = package.config:sub(1, 1)
  local here = ({r.get_action_context()})[2]:match("(.*" .. sep .. ")") or ""
  package.path = here .. "lib" .. sep .. "?.lua;" ..
                 here .. ".." .. sep .. "NPH" .. sep .. "lib" .. sep .. "?.lua;" ..
                 r.GetResourcePath() .. "/Scripts/NPH REAPER Suite/NPH/lib/?.lua;" ..
                 package.path
end

local okSafe, safe = pcall(require, "nph_safe")
if not okSafe then
  r.ShowMessageBox("StageRig could not load NPH/lib/nph_safe.lua:\n\n" ..
    tostring(safe), "StageRig", 0); return
end
local okCompat, compat = pcall(require, "nph_imgui")
if okCompat then compat.install() end

if not safe.require("StageRig", { imgui = true }) then return end

local EXT   = "NPH_STAGERIG"
local PROJ  = 0

-- Note tracker parameter indices (see nph_note_tracker.jsfx sliders).
local P_GATE, P_RELEASE = 0, 1

local RING_DEFAULT = 2.0   -- seconds the outgoing patch is allowed to decay

--------------------------------------------------------------------------------
-- setlist, loaded defensively
--   A corrupt or partial ExtState must never brick a show. Anything that does
--   not parse is skipped and counted; the set still loads.
--------------------------------------------------------------------------------

local setlist, loadErrors, concertName = {}, 0, ""

local function loadSetlist()
  setlist, loadErrors = {}, 0
  local _, raw = r.GetProjExtState(PROJ, EXT, "setlist")
  local _, cn  = r.GetProjExtState(PROJ, EXT, "concert")
  concertName = cn or ""
  if not raw or raw == "" then return end

  for chunk in (raw .. "\30"):gmatch("(.-)\30") do
    if chunk ~= "" then
      local f = {}
      for part in (chunk .. "\31"):gmatch("(.-)\31") do f[#f+1] = part end
      if #f >= 5 then
        local tracks = {}
        for g in (f[5] .. ","):gmatch("(.-),") do
          if g ~= "" then tracks[#tracks+1] = g end
        end
        setlist[#setlist+1] = {
          name   = f[2],
          folder = f[3],
          tempo  = tonumber(f[4]),
          tracks = tracks,
        }
      else
        loadErrors = loadErrors + 1
      end
    end
  end
end

--------------------------------------------------------------------------------
-- patch operations, all GUID-resolved per call
--------------------------------------------------------------------------------

local function patchTracks(p)
  local out = {}
  if not p then return out end
  local all = { p.folder }
  for _, g in ipairs(p.tracks) do all[#all+1] = g end
  local map = safe.guidMap(PROJ)
  for _, g in ipairs(all) do
    local t = map[g]
    if t then out[#out+1] = t end
  end
  return out
end

local function setMute(p, muted)
  for _, t in ipairs(patchTracks(p)) do
    safe.setVal(PROJ, t, "B_MUTE", muted and 1 or 0)
  end
end

-- The gate lives on the note tracker, which build put at FX slot 0. Verify the
-- plugin is really there before writing a parameter: on a track where the JSFX
-- failed to load, slot 0 is the instrument, and writing param 0 would move
-- something real.
local function forEachTracker(p, fn)
  for _, t in ipairs(patchTracks(p)) do
    if r.TrackFX_GetCount(t) > 0 then
      local ok, nm = r.TrackFX_GetFXName(t, 0, "")
      if ok and nm and nm:lower():find("note tracker") then fn(t, 0) end
    end
  end
end

local function setGate(p, closed)
  forEachTracker(p, function(t, fx)
    r.TrackFX_SetParam(t, fx, P_GATE, closed and 1 or 0)
  end)
end

local function flush(p)
  -- The JSFX triggers on a rising edge, so pulse it.
  forEachTracker(p, function(t, fx)
    r.TrackFX_SetParam(t, fx, P_RELEASE, 1)
  end)
  forEachTracker(p, function(t, fx)
    r.TrackFX_SetParam(t, fx, P_RELEASE, 0)
  end)
end

--------------------------------------------------------------------------------
-- the state machine
--   Every request becomes an intent. Nothing acts directly from the UI, so a
--   double-tap during a switch cannot interleave two sequences.
--------------------------------------------------------------------------------

local current, pending, ringTime = nil, nil, RING_DEFAULT
local status = "no setlist"

local function goTo(i)
  local target = setlist[i]
  if not target then return end
  if current == i and not pending then return end

  -- 1. incoming first
  setGate(target, false)
  setMute(target, false)

  local outgoing = current and setlist[current] or nil
  if outgoing and outgoing ~= target then
    -- 2. stop new notes reaching the outgoing patch, let it ring
    setGate(outgoing, true)
    if pending then
      -- a switch was already in flight: finish that one now rather than
      -- leaving its patch gated and audible forever
      flush(pending.p); setMute(pending.p, true); setGate(pending.p, false)
    end
    pending = { p = outgoing, at = r.time_precise() + ringTime }
  end

  current = i
  status = "playing: " .. target.name
end

local function tickSwitch()
  if pending and r.time_precise() >= pending.at then
    -- 4. flush held notes and sustain, then mute
    flush(pending.p)
    setMute(pending.p, true)
    setGate(pending.p, false)   -- reopen so it is ready next time
    pending = nil
  end
end

local function panic(hard)
  for i, p in ipairs(setlist) do
    if hard or i ~= current then
      setGate(p, true); flush(p); setMute(p, true); setGate(p, false)
    end
  end
  pending = nil
  if hard then
    current = nil
    status = "PANIC - everything muted"
  else
    if current then setMute(setlist[current], false) end
    status = "panic: cleared all but current"
  end
end

--------------------------------------------------------------------------------
-- UI
--------------------------------------------------------------------------------

local ctx = r.ImGui_CreateContext('StageRig')
local FBIG  = r.ImGui_CreateFont('sans-serif', 46)
local FMED  = r.ImGui_CreateFont('sans-serif', 22)
local FSML  = r.ImGui_CreateFont('sans-serif', 14)
r.ImGui_Attach(ctx, FBIG); r.ImGui_Attach(ctx, FMED); r.ImGui_Attach(ctx, FSML)

local VIOLET = 0x8a5cf0ff
local DIM    = 0x8b93a3ff

local function trackColour(p)
  local map = safe.guidMap(PROJ)
  local t = p and map[p.folder]
  if not t then return VIOLET end
  local c = safe.getVal(PROJ, t, "I_CUSTOMCOLOR", 0) or 0
  if c == 0 then return VIOLET end
  local rr, gg, bb = r.ColorFromNative(math.floor(c) & 0xFFFFFF)
  return (rr << 24) | (gg << 16) | (bb << 8) | 0xff
end

loadSetlist()
if #setlist > 0 then status = "ready - " .. #setlist .. " patches" end

local lastSig, lastSigAt = "", 0

local function frame()
  -- Watchdog: GetProjectStateChangeCount does NOT move on track edits (probed
  -- directly - it sat still through insert, rename and delete), so diff a cheap
  -- signature instead, throttled so it stays free on a big session.
  local now = r.time_precise()
  if now - lastSigAt > 0.25 then
    lastSigAt = now
    local sig = safe.projSignature(PROJ)
    if sig ~= lastSig then lastSig = sig end
  end

  tickSwitch()

  r.ImGui_PushFont(ctx, FSML)
  r.ImGui_TextColored(ctx, DIM,
    (concertName ~= "" and concertName or "no concert loaded") ..
    (loadErrors > 0 and ("   ·   %d unreadable setlist entries skipped"):format(loadErrors) or ""))
  r.ImGui_PopFont(ctx)

  if #setlist == 0 then
    r.ImGui_Dummy(ctx, 1, 12)
    r.ImGui_PushFont(ctx, FMED)
    r.ImGui_Text(ctx, "No setlist in this project.")
    r.ImGui_PopFont(ctx)
    r.ImGui_PushFont(ctx, FSML)
    r.ImGui_TextColored(ctx, DIM,
      "Run StageRig Build in an empty project tab to create one.")
    r.ImGui_PopFont(ctx)
    if r.ImGui_Button(ctx, "Reload setlist") then loadSetlist() end
    return
  end

  -- CURRENT
  local cur = current and setlist[current] or nil
  r.ImGui_Dummy(ctx, 1, 6)
  r.ImGui_PushFont(ctx, FBIG)
  r.ImGui_TextColored(ctx, cur and trackColour(cur) or DIM,
    cur and cur.name or "—")
  r.ImGui_PopFont(ctx)

  -- NEXT
  local nxt = current and setlist[current + 1] or setlist[1]
  r.ImGui_PushFont(ctx, FSML)
  r.ImGui_TextColored(ctx, DIM, "NEXT")
  r.ImGui_PopFont(ctx)
  r.ImGui_PushFont(ctx, FMED)
  r.ImGui_TextColored(ctx, nxt and trackColour(nxt) or DIM, nxt and nxt.name or "end of set")
  r.ImGui_PopFont(ctx)

  r.ImGui_Dummy(ctx, 1, 8)
  if nxt and r.ImGui_Button(ctx, "GO  ->  " .. nxt.name, 260, 46) then
    for i, p in ipairs(setlist) do if p == nxt then goTo(i) end end
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "PANIC", 110, 46) then panic(false) end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "ALL OFF", 110, 46) then panic(true) end

  r.ImGui_Dummy(ctx, 1, 10)
  r.ImGui_Separator(ctx)
  r.ImGui_Dummy(ctx, 1, 6)

  -- the set
  r.ImGui_PushFont(ctx, FMED)
  for i, p in ipairs(setlist) do
    local isCur = (i == current)
    local label = ("%d.  %s"):format(i, p.name)
    if isCur then
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), trackColour(p) & 0xFFFFFF60)
    end
    if r.ImGui_Button(ctx, label, 340, 40) then goTo(i) end
    if isCur then r.ImGui_PopStyleColor(ctx) end
    if p.tempo and p.tempo > 0 then
      r.ImGui_SameLine(ctx)
      r.ImGui_PushFont(ctx, FSML)
      r.ImGui_TextColored(ctx, DIM, ("%.0f bpm"):format(p.tempo))
      r.ImGui_PopFont(ctx)
    end
  end
  r.ImGui_PopFont(ctx)

  r.ImGui_Dummy(ctx, 1, 10)
  r.ImGui_PushFont(ctx, FSML)
  local changed, v = r.ImGui_SliderDouble(ctx, "ring-out seconds", ringTime, 0.5, 6.0, "%.1f s")
  if changed then ringTime = v end
  r.ImGui_TextColored(ctx, DIM, status ..
    (pending and ("   ·   " .. pending.p.name .. " ringing out") or ""))
  r.ImGui_PopFont(ctx)
end

local function loop()
  r.ImGui_SetNextWindowSize(ctx, 460, 640, r.ImGui_Cond_FirstUseEver())
  local visible, open = r.ImGui_Begin(ctx, 'StageRig', true)
  if visible then
    local ok, err = pcall(frame)
    if not ok then
      r.ImGui_Text(ctx, "error: " .. tostring(err))
    end
    r.ImGui_End(ctx)
  end
  if open then r.defer(loop) end
end

r.defer(loop)
