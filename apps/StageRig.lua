-- @description StageRig
-- @version 0.2.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about
--   Live patch switching for REAPER. Reads a setlist built by StageRig Build,
--   shows a stage view with NOW and NEXT, and switches patches without cutting
--   off what is still ringing. Bind "StageRig Next" / "StageRig Panic" to a
--   footswitch for hands-free use.
--   Requires the "Shared Libraries" package from this same repository
--   (right-click the repository in ReaPack > Install All).
-- @changelog
--   0.2.0 - works on ReaImGui 0.10 (the 0.1.0 font calls died on open).
--           New shared look (nt_ui). Switching back to a patch that is still
--           ringing out no longer mutes it. Flush pulse is now edge-safe.
--           Missing patch tracks are reported, not silently skipped.
--           Space / Enter / Right = GO next when the window is focused, and
--           the "StageRig Next" / "StageRig Panic" scripts drive it hands-free.
--   0.1.0 - first version. Switching, panic, stage view.

--[[
  StageRig  (violet - performance)
  ----------------------------------------------------------------------------
  THE SWITCH, in the order that matters:

    1. unmute the INCOMING patch first, so it is already playable
    2. close the gate on the OUTGOING patch, so no new notes reach it while
       what is already sounding continues
    3. let it ring (default 2.0 s, adjustable)
    4. flush: matching note-offs + CC64=0, then mute

  Notes are handled by nt_note_tracker.jsfx at audio rate. This script only
  decides WHEN, and sets parameters. Nothing is created, destroyed or
  reconfigured during a set.

  Hands-free: any script/footswitch can write the ExtState mailbox
      reaper.SetExtState("NT_STAGERIG", "cmd", "next" | "prev" | "panic" | "alloff" | "go:<n>", false)
  and this window acts on it within a frame. See "StageRig Next.lua".
--]]

local r = reaper

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
  r.ShowMessageBox("StageRig needs the 'Shared Libraries' package.\n\n" ..
    "Extensions > ReaPack > Browse packages > search 'Nathaniel Tools' > Shared Libraries > Install.\n" ..
    "(Or right-click the Nathaniel Tools repository > Install All.)", "StageRig", 0)
  return
end
do local ok, compat = pcall(require, "nt_imgui"); if ok then compat.install() end end
if not safe.require("StageRig", { imgui = true }) then return end

local APP  = "StageRig"
local EXT  = "NT_STAGERIG"
local PROJ = 0
local T    = ui.tokens

local P_GATE, P_RELEASE = 0, 1     -- nt_note_tracker slider indices
local RING_DEFAULT = 2.0

--------------------------------------------------------------------------------
-- setlist
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
      for part in (chunk .. "\31"):gmatch("(.-)\31") do f[#f + 1] = part end
      if #f >= 5 then
        local tracks = {}
        for g in (f[5] .. ","):gmatch("(.-),") do if g ~= "" then tracks[#tracks + 1] = g end end
        setlist[#setlist + 1] = { name = f[2], folder = f[3], tempo = tonumber(f[4]), tracks = tracks }
      else
        loadErrors = loadErrors + 1
      end
    end
  end
end

--------------------------------------------------------------------------------
-- patch operations, GUID-resolved per call
--------------------------------------------------------------------------------
-- returns live tracks AND how many of the patch's tracks are gone
local function patchTracks(p)
  local out, missing = {}, 0
  if not p then return out, 0 end
  local all = { p.folder }
  for _, g in ipairs(p.tracks) do all[#all + 1] = g end
  local map = safe.guidMap(PROJ)
  for _, g in ipairs(all) do
    local t = map[g]
    if t then out[#out + 1] = t else missing = missing + 1 end
  end
  return out, missing
end

local function setMute(p, muted)
  for _, t in ipairs(patchTracks(p)) do safe.setVal(PROJ, t, "B_MUTE", muted and 1 or 0) end
end

local function forEachTracker(p, fn)
  for _, t in ipairs(patchTracks(p)) do
    if r.TrackFX_GetCount(t) > 0 then
      local ok, nm = r.TrackFX_GetFXName(t, 0, "")
      if ok and nm and nm:lower():find("note tracker") then fn(t, 0) end
    end
  end
end

local function setGate(p, closed)
  forEachTracker(p, function(t, fx) r.TrackFX_SetParam(t, fx, P_GATE, closed and 1 or 0) end)
end

-- Flush = a rising edge on the RELEASE slider. Setting 1 then 0 inside one
-- defer frame can collapse into "0" by the time the audio thread looks, so
-- we set 1 now and reset to 0 on a later frame (the JSFX also self-resets).
local flushArmed = {}   -- { {p=, at=} }
local function flush(p)
  forEachTracker(p, function(t, fx) r.TrackFX_SetParam(t, fx, P_RELEASE, 1) end)
  flushArmed[#flushArmed + 1] = { p = p, at = r.time_precise() + 0.12 }
end
local function tickFlush()
  local now = r.time_precise()
  for i = #flushArmed, 1, -1 do
    local f = flushArmed[i]
    if now >= f.at then
      forEachTracker(f.p, function(t, fx) r.TrackFX_SetParam(t, fx, P_RELEASE, 0) end)
      table.remove(flushArmed, i)
    end
  end
end

--------------------------------------------------------------------------------
-- the state machine
--------------------------------------------------------------------------------
local current, pending, ringTime = nil, nil, RING_DEFAULT
local ctx = r.ImGui_CreateContext(APP)
ui.fonts(ctx)
local function say(m, l) ui.say(ctx, m, l) end

local function goTo(i)
  local target = setlist[i]
  if not target then return end
  if current == i and not pending then return end

  -- 1. incoming first
  setGate(target, false)
  setMute(target, false)

  -- coming BACK to the patch that is still ringing out: it is simply current
  -- again - cancel the pending mute, never flush it.
  if pending and pending.p == target then pending = nil end

  local outgoing = current and setlist[current] or nil
  if outgoing and outgoing ~= target then
    setGate(outgoing, true)                       -- 2. no new notes, let it ring
    if pending and pending.p ~= outgoing then
      -- a different switch was already in flight: finish that one now
      flush(pending.p); setMute(pending.p, true); setGate(pending.p, false)
    end
    pending = { p = outgoing, at = r.time_precise() + ringTime }
  end
  current = i
  local _, missing = patchTracks(target)
  if missing > 0 then say(("Now: %s  (%d of its tracks are missing from the project)"):format(target.name, missing), "warn")
  else say("Now: " .. target.name, "ok") end
end

local function tickSwitch()
  if pending and r.time_precise() >= pending.at then
    flush(pending.p); setMute(pending.p, true); setGate(pending.p, false)   -- 4.
    pending = nil
  end
end

local function panic(hard)
  for i, p in ipairs(setlist) do
    if hard or i ~= current then setGate(p, true); flush(p); setMute(p, true); setGate(p, false) end
  end
  pending = nil
  if hard then current = nil; say("ALL OFF - every patch muted and flushed.", "danger")
  else
    if current then setMute(setlist[current], false) end
    say("Panic: everything except the current patch muted and flushed.", "warn")
  end
end

local function goNext()
  local i = current and current + 1 or 1
  if setlist[i] then goTo(i) else say("End of set.", "info") end
end
local function goPrev()
  local i = current and current - 1 or 1
  if setlist[i] then goTo(i) else say("Already at the first patch.", "info") end
end

-- hands-free mailbox (footswitch scripts write here)
local function pollMailbox()
  local cmd = r.GetExtState(EXT, "cmd")
  if cmd == nil or cmd == "" then return end
  r.DeleteExtState(EXT, "cmd", false)
  if cmd == "next" then goNext()
  elseif cmd == "prev" then goPrev()
  elseif cmd == "panic" then panic(false)
  elseif cmd == "alloff" then panic(true)
  else
    local n = tonumber(cmd:match("^go:(%d+)$"))
    if n then goTo(n) end
  end
end

--------------------------------------------------------------------------------
-- UI
--------------------------------------------------------------------------------
local function patchColour(p)
  local map = safe.guidMap(PROJ)
  local t = p and map[p.folder]
  if not t then return ui.accents.violet end
  local c = safe.getVal(PROJ, t, "I_CUSTOMCOLOR", 0) or 0
  if c == 0 then return ui.accents.violet end
  return ui.fromNative(math.floor(c) & 0xFFFFFF) or ui.accents.violet
end

loadSetlist()
if #setlist > 0 then say(("Ready - %d patches loaded."):format(#setlist), "info") end

local lastSig, lastSigAt = "", 0

local function frame()
  local now = r.time_precise()
  if now - lastSigAt > 0.25 then
    lastSigAt = now
    local sig = safe.projSignature(PROJ)
    if sig ~= lastSig then
      if lastSig ~= "" then loadSetlist(); say("Project changed - setlist re-read.", "info") end
      lastSig = sig
    end
  end
  tickSwitch(); tickFlush(); pollMailbox()

  ui.header(ctx, APP, concertName ~= "" and concertName or "live patch switching", function() ui.dockToggle(ctx) end, 70)
  if loadErrors > 0 then ui.hint(ctx, ("%d unreadable setlist entries were skipped."):format(loadErrors)) end

  if #setlist == 0 then
    ui.empty(ctx, "No setlist in this project",
      "Run 'StageRig Build' in an EMPTY project tab to build the rig, then open StageRig there.",
      { button = "Reload setlist", onClick = loadSetlist })
    ui.pushToBottom(ctx, 44)
    ui.status(ctx, { idle = "Waiting for a setlist." })
    return
  end

  -- keyboard: Space / Enter / Right = next; Left = previous
  if r.ImGui_IsWindowFocused(ctx) and not r.ImGui_IsAnyItemActive(ctx) then
    local function pressed(k) local e = ui.E(k); return e and r.ImGui_IsKeyPressed(ctx, e, false) end
    if pressed("Key_Space") or pressed("Key_Enter") or pressed("Key_RightArrow") then goNext() end
    if pressed("Key_LeftArrow") then goPrev() end
  end

  -- NOW
  local cur = current and setlist[current] or nil
  ui.vspace(ctx, 4)
  ui.pushFont(ctx, "small", true); r.ImGui_TextColored(ctx, T.muted, "NOW"); ui.popFont(ctx)
  local nowName = cur and cur.name or "not started"
  -- shrink the big name if it would not fit the window
  local availW = r.ImGui_GetContentRegionAvail(ctx)
  ui.pushFont(ctx, "huge", true)
  local tw = r.ImGui_CalcTextSize(ctx, nowName)
  ui.popFont(ctx)
  ui.pushFont(ctx, tw > availW - 8 and "big" or "huge", true)
  r.ImGui_TextColored(ctx, cur and patchColour(cur) or T.dim, nowName)
  ui.popFont(ctx)
  if cur then
    local _, missing = patchTracks(cur)
    if missing > 0 then r.ImGui_SameLine(ctx, 0, 12); ui.pill(ctx, ("%d tracks missing"):format(missing), T.danger) end
    if pending then r.ImGui_SameLine(ctx, 0, 12); ui.pill(ctx, pending.p.name .. " ringing out", T.warn) end
  end

  -- NEXT
  local nxt = current and setlist[current + 1] or setlist[1]
  ui.pushFont(ctx, "small", true); r.ImGui_TextColored(ctx, T.muted, "NEXT"); ui.popFont(ctx)
  ui.pushFont(ctx, "big")
  r.ImGui_TextColored(ctx, nxt and patchColour(nxt) or T.dim, nxt and nxt.name or "end of set")
  ui.popFont(ctx)

  ui.vspace(ctx, 8)
  local w = r.ImGui_GetContentRegionAvail(ctx)
  local goW = math.max(200, w - 2 * 110 - 2 * 8)
  ui.pushFont(ctx, "title", true)
  if ui.button(ctx, nxt and ("GO  >  " .. nxt.name) or "GO", { kind = "primary", w = goW, h = 52, disabled = not nxt,
      tip = "Switch to the next patch. Space, Enter or Right arrow does the same when this window is focused; bind 'StageRig Next' to a footswitch for hands-free." }) then goNext() end
  ui.popFont(ctx)
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "PANIC", { kind = "primary", colour = T.warn, w = 110, h = 52,
      tip = "Mute and flush everything EXCEPT the current patch. Use when something is droning." }) then panic(false) end
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "ALL OFF", { kind = "danger", w = 110, h = 52,
      tip = "Mute and flush every patch, including the current one. Silence, instantly." }) then panic(true) end

  ui.section(ctx, "The set")
  local _, availH = r.ImGui_GetContentRegionAvail(ctx)
  local listH = math.max(80, availH - 118)
  if r.ImGui_BeginChild(ctx, "##set", 0, listH, 0) then
    local cw = r.ImGui_GetContentRegionAvail(ctx)
    for i, p in ipairs(setlist) do
      local isCur = (i == current)
      local isNext = (nxt == p)
      local col = patchColour(p)
      r.ImGui_PushID(ctx, i)
      local n = 0
      local function pc(name, c) local e = ui.E("Col_" .. name); if e then r.ImGui_PushStyleColor(ctx, e, c); n = n + 1 end end
      if isCur then pc("Button", ui.alpha(col, 0.55)); pc("ButtonHovered", ui.alpha(col, 0.65)); pc("ButtonActive", ui.alpha(col, 0.8)); pc("Text", T.white)
      elseif isNext then pc("Button", ui.alpha(col, 0.18)); pc("ButtonHovered", ui.alpha(col, 0.3)); pc("ButtonActive", ui.alpha(col, 0.4)) end
      ui.pushFont(ctx, "title")
      local label = ("%d.   %s"):format(i, p.name)
      if p.tempo and p.tempo > 0 then label = label .. ("      %.0f bpm"):format(p.tempo) end
      if r.ImGui_Button(ctx, label, cw, 40) then goTo(i) end
      ui.popFont(ctx)
      r.ImGui_PopStyleColor(ctx, n)
      ui.tip(ctx, isCur and "Playing now." or ("Jump straight to " .. p.name .. "."))
      r.ImGui_PopID(ctx)
    end
    r.ImGui_EndChild(ctx)
  end

  r.ImGui_SetNextItemWidth(ctx, 220)
  local changed, v = r.ImGui_SliderDouble(ctx, "##ring", ringTime, 0.5, 6.0, "ring-out %.1f s")
  if changed then ringTime = v end
  ui.tip(ctx, "How long the outgoing patch is allowed to keep sounding before it is muted.")
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "Reload setlist", { kind = "ghost", small = true, tip = "Re-read the setlist stored in this project." }) then loadSetlist(); say("Setlist reloaded.", "info") end

  ui.status(ctx, { idle = "Press GO, Space, or a footswitch bound to 'StageRig Next'." })
end

local function loop()
  local open = ui.window(ctx, { title = APP, accent = ui.accents.violet, w = 520, h = 680, minW = 380, minH = 420, dock = false }, frame)
  if open then r.defer(loop) end
end
r.defer(loop)
