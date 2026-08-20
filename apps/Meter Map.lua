-- @description Meter Map
-- @version 1.0.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about
--   Time signatures and their groupings, without touching the tempo.
--
--   Every marker this makes is flagged "does not set tempo", so nothing you do
--   here can move a beat. You pick the meter and the grouping first, look at
--   it, and press APPLY once - it replaces whatever was on that bar instead of
--   stacking another marker on top.
--
--   The list shows every tempo and time-signature marker in the project, what
--   bar it sits on and whether it changes tempo, so a session that has been
--   messed about with can be read and cleaned in one place.
--
--   Requires the "Shared Libraries" package from this same repository.
-- @changelog
--   1.0.0 - first version.

local r = reaper
do
  local sep = package.config:sub(1, 1)
  local here = ({ r.get_action_context() })[2]:match("(.*" .. sep .. ")") or ""
  package.path = here .. ".." .. sep .. "scripts" .. sep .. "lib" .. sep .. "?.lua;" ..
                 r.GetResourcePath() .. "/Scripts/Nathaniel Tools/scripts/lib/?.lua;" .. package.path
end
local okSafe, safe = pcall(require, "nt_safe")
local okUi,   ui   = pcall(require, "nt_ui")
if not (okSafe and okUi) then
  r.ShowMessageBox("Meter Map needs the 'Shared Libraries' package.\n\nExtensions > ReaPack > Browse packages > Nathaniel Tools > Shared Libraries > Install (or Install All).", "Meter Map", 0)
  return
end
do local ok, compat = pcall(require, "nt_imgui"); if ok then compat.install() end end
if not safe.require("Meter Map", { imgui = true }) then return end

local APP = "Meter Map"
local T = ui.tokens
local ACCENT = ui.accents.amber
local ctx = r.ImGui_CreateContext(APP)
ui.fonts(ctx)

--------------------------------------------------------------------------------
-- reading the map
--------------------------------------------------------------------------------
local function cursorMeasure()
  local pos = r.GetCursorPosition()
  local _, measures = r.TimeMap2_timeToBeats(0, pos)
  return measures, r.TimeMap2_beatsToTime(0, 0, measures)
end

local function meterAt(time)
  local num, den = r.TimeMap_GetTimeSigAtTime(0, time)
  return math.floor((num or 4) + 0.5), math.floor((den or 4) + 0.5)
end

-- Tempo in force at a point, taken from the map rather than computed, so it can
-- be handed straight back unchanged.
local function tempoAt(time)
  local idx = r.FindTempoTimeSigMarker(0, time)
  if idx and idx >= 0 then
    local ok, _, _, _, bpm = r.GetTempoTimeSigMarker(0, idx)
    if ok and bpm and bpm > 0 then return bpm end
  end
  return r.Master_GetTempo()
end

local function markers()
  local out = {}
  for i = 0, r.CountTempoTimeSigMarkers(0) - 1 do
    local ok, timepos, measurepos, beatpos, bpm, num, den, linear = r.GetTempoTimeSigMarker(0, i)
    if ok then
      local flag = r.GetSetTempoTimeSigMarkerFlag and r.GetSetTempoTimeSigMarkerFlag(0, i, 0, false) or 0
      out[#out + 1] = {
        index = i, time = timepos, measure = measurepos, beat = beatpos,
        bpm = bpm, num = num, den = den, linear = linear,
        setsTempo = (flag & 2) == 0,
        setsMeter = (flag & 1) ~= 0,
      }
    end
  end
  return out
end

--------------------------------------------------------------------------------
-- writing, without ever moving a beat
--------------------------------------------------------------------------------
-- Everything goes through here. The marker is written with the tempo that was
-- already in force and then flagged "does not set tempo", so the tempo map is
-- left exactly as it was. This is the bug that made a mess of the ruler: a
-- marker written with a computed tempo silently becomes a tempo change.
local function writeMeter(measure, num, den)
  local time = r.TimeMap2_beatsToTime(0, 0, measure)
  local bpm = tempoAt(time)

  -- replace rather than stack: if this bar already carries a marker, edit it
  local target = -1
  for _, m in ipairs(markers()) do
    if m.measure == measure then target = m.index; break end
  end

  local ok = r.SetTempoTimeSigMarker(0, target, -1, measure, 0, bpm, num, den, false)
  if not ok then return false end

  if target < 0 then
    for _, m in ipairs(markers()) do
      if m.measure == measure then target = m.index; break end
    end
  end
  if target >= 0 and r.GetSetTempoTimeSigMarkerFlag then
    -- 1 = sets the time signature and starts a new measure
    -- 2 = does NOT set the tempo
    r.GetSetTempoTimeSigMarkerFlag(0, target, 1 | 2, true)
  end
  return true
end

local function clearMarkersBetween(firstMeasure, lastMeasure)
  local doomed = {}
  for _, m in ipairs(markers()) do
    if m.measure >= firstMeasure and m.measure <= lastMeasure and m.measure > 0 then
      doomed[#doomed + 1] = m.index
    end
  end
  table.sort(doomed, function(a, b) return a > b end)   -- back to front, indexes shift
  for _, index in ipairs(doomed) do r.DeleteTempoTimeSigMarker(0, index) end
  return #doomed
end

--------------------------------------------------------------------------------
-- groupings
--------------------------------------------------------------------------------
-- How a meter is normally felt. Jason's rule: 5/8 is 2+3, not 3+2.
local FEEL = {
  [5] = { 2, 3 }, [7] = { 3, 4 }, [8] = { 3, 3, 2 }, [9] = { 3, 3, 3 },
  [10] = { 3, 3, 4 }, [11] = { 3, 3, 3, 2 }, [12] = { 3, 3, 3, 3 },
  [13] = { 7, 6 }, [15] = { 7, 8 }, [16] = { 3, 3, 3, 3, 4 },
}
local function defaultGroups(num)
  if FEEL[num] then
    local copy = {}
    for i, v in ipairs(FEEL[num]) do copy[i] = v end
    return copy
  end
  if num <= 4 then return { num } end
  local half = math.floor(num / 2)
  return { half, num - half }
end

local function sum(t) local s = 0 for _, v in ipairs(t) do s = s + v end return s end

--------------------------------------------------------------------------------
-- state
--------------------------------------------------------------------------------
local pending = nil        -- the split being designed, applied only on APPLY
local status = ""
local lastMeasure = nil

local function resetPending(num)
  pending = defaultGroups(num)
end

--------------------------------------------------------------------------------
local function drawFrame()
  local measure, measureTime = cursorMeasure()
  local num, den = meterAt(measureTime)
  local bpm = tempoAt(measureTime)

  if lastMeasure ~= measure or pending == nil then
    lastMeasure = measure
    resetPending(num)
  end

  -- ---- where you are ------------------------------------------------------
  ui.pushFont(ctx, "title", true)
  r.ImGui_Text(ctx, string.format("Bar %d    %d/%d", measure + 1, num, den))
  ui.popFont(ctx)
  r.ImGui_SameLine(ctx)
  ui.dim(ctx, string.format("   %.2f BPM  (never changed from here)", bpm))

  r.ImGui_Dummy(ctx, 1, 6)

  -- ---- the meter itself ---------------------------------------------------
  ui.dim(ctx, "METER")
  r.ImGui_SameLine(ctx)
  local beats = sum(pending)
  if ui.button(ctx, "-", { w = 26, h = 24, small = true, disabled = beats <= 1,
    tip = "One beat fewer in the bar." }) then
    resetPending(math.max(1, beats - 1))
  end
  r.ImGui_SameLine(ctx)
  ui.pushFont(ctx, "title", true)
  r.ImGui_Text(ctx, string.format("%d/%d", beats, den))
  ui.popFont(ctx)
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "+", { w = 26, h = 24, small = true, disabled = beats >= 32,
    tip = "One beat more in the bar." }) then
    resetPending(math.min(32, beats + 1))
  end

  r.ImGui_SameLine(ctx)
  r.ImGui_Dummy(ctx, 10, 1)
  r.ImGui_SameLine(ctx)
  for _, d in ipairs({ 2, 4, 8, 16 }) do
    r.ImGui_SameLine(ctx)
    if ui.button(ctx, "/" .. d, { kind = (d == den) and "primary" or "secondary", colour = ACCENT,
      w = 38, h = 24, small = true, tip = "Beat is a " .. d .. "th note." }) then
      den = d
    end
  end

  -- ---- the grouping -------------------------------------------------------
  r.ImGui_Dummy(ctx, 1, 6)
  ui.dim(ctx, "FELT AS")
  r.ImGui_SameLine(ctx)
  for i, count in ipairs(pending) do
    if i > 1 then
      r.ImGui_SameLine(ctx)
      ui.dim(ctx, "+")
      r.ImGui_SameLine(ctx)
    end
    if ui.button(ctx, tostring(count), { kind = "secondary", w = 30, h = 24, small = true,
      tip = "Click to move a beat from this group to the next one." }) then
      if #pending > 1 and count > 1 then
        local nextIndex = (i < #pending) and (i + 1) or (i - 1)
        pending[i] = count - 1
        pending[nextIndex] = pending[nextIndex] + 1
      end
    end
  end
  r.ImGui_SameLine(ctx)
  r.ImGui_Dummy(ctx, 8, 1)
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "SPLIT", { w = 56, h = 24, small = true, disabled = beats < 2,
    tip = "Break the last group in two." }) then
    local last = pending[#pending]
    if last >= 2 then
      local half = math.floor(last / 2)
      pending[#pending] = last - half
      pending[#pending + 1] = half
    end
  end
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "JOIN", { w = 50, h = 24, small = true, disabled = #pending < 2,
    tip = "Put the last two groups back together." }) then
    local last = table.remove(pending)
    pending[#pending] = pending[#pending] + last
  end
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "RESET", { kind = "ghost", w = 56, h = 24, small = true,
    tip = "Back to how this meter is normally felt." }) then resetPending(beats) end

  -- ---- apply, once --------------------------------------------------------
  r.ImGui_Dummy(ctx, 1, 6)
  local asBars = #pending > 1
  if ui.button(ctx, string.format("APPLY  %d/%d", beats, den), {
    kind = "primary", colour = ACCENT, w = 130, h = 30,
    tip = "Write this meter onto bar " .. (measure + 1) .. ". Replaces what is there; never touches the tempo."
  }) then
    r.Undo_BeginBlock()
    writeMeter(measure, beats, den)
    r.Undo_EndBlock(string.format("Meter Map: bar %d to %d/%d", measure + 1, beats, den), -1)
    r.UpdateTimeline()
    status = string.format("Bar %d is now %d/%d. Tempo untouched.", measure + 1, beats, den)
  end

  if asBars then
    r.ImGui_SameLine(ctx)
    if ui.button(ctx, "APPLY AS BARS", { w = 140, h = 30,
      tip = "Lay the grouping out as consecutive bars - " .. table.concat(pending, "+") ..
            " becomes one bar each - so REAPER's click accents every group." }) then
      r.Undo_BeginBlock()
      clearMarkersBetween(measure, measure + #pending)
      local at = measure
      for _, count in ipairs(pending) do
        writeMeter(at, count, den)
        at = at + 1
      end
      writeMeter(at, num, den)      -- put the old meter back after the run
      r.Undo_EndBlock("Meter Map: " .. table.concat(pending, "+") .. " as bars", -1)
      r.UpdateTimeline()
      status = "Laid out as " .. table.concat(pending, "+") .. " over " .. #pending .. " bars. Tempo untouched."
    end
  end

  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "CLEAR THIS BAR", { kind = "ghost", w = 130, h = 30,
    tip = "Remove the marker on this bar, so it inherits the meter before it." }) then
    r.Undo_BeginBlock()
    local n = clearMarkersBetween(measure, measure)
    r.Undo_EndBlock("Meter Map: clear bar " .. (measure + 1), -1)
    r.UpdateTimeline()
    status = n > 0 and ("Removed the marker on bar " .. (measure + 1) .. ".") or "Nothing on that bar to remove."
  end

  if status ~= "" then
    r.ImGui_Dummy(ctx, 1, 4)
    ui.dim(ctx, status)
  end

  -- ---- the map ------------------------------------------------------------
  r.ImGui_Dummy(ctx, 1, 8)
  local list = markers()
  ui.dim(ctx, string.format("MARKERS IN THIS PROJECT (%d)", #list))
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "REMOVE ALL METER MARKERS", { kind = "danger", w = 200, h = 22, small = true,
    disabled = #list == 0,
    tip = "Strip every tempo/time-signature marker after the first bar. Use this to undo a mess." }) then
    r.Undo_BeginBlock()
    local n = clearMarkersBetween(1, 1000000)
    r.Undo_EndBlock("Meter Map: remove all meter markers", -1)
    r.UpdateTimeline()
    status = "Removed " .. n .. " marker(s)."
  end

  if #list == 0 then
    ui.hint(ctx, "None - the whole project runs on one meter and one tempo.")
  else
    for _, m in ipairs(list) do
      local label = string.format("bar %-5d  %d/%-3d  %6.2f BPM   %s",
        m.measure + 1, m.num, m.den, m.bpm,
        m.setsTempo and "changes tempo" or "meter only")
      ui.pushFont(ctx, "small")
      r.ImGui_TextColored(ctx, m.setsTempo and T.warn or T.muted, label)
      ui.popFont(ctx)
      if r.ImGui_IsItemClicked and r.ImGui_IsItemClicked(ctx) then
        r.SetEditCurPos(m.time, true, false)
      end
      ui.tip(ctx, "Click to put the cursor on this marker.")
    end
  end
end

--------------------------------------------------------------------------------
local reported = false
local function frame()
  local ok, err = pcall(drawFrame)
  if not ok then
    if not reported then
      reported = true
      local fh = io.open(r.GetResourcePath() .. "/nt_click_strip_error.log", "a")
      if fh then fh:write(os.date("%Y-%m-%d %H:%M:%S ") .. "Meter Map: " .. tostring(err) .. "\n"); fh:close() end
    end
    r.ImGui_TextColored(ctx, T.danger, "Meter Map: " .. tostring(err))
  end
end

local function loop()
  local open = ui.window(ctx, { title = APP, accent = ACCENT, w = 760, h = 420, minW = 380, minH = 220 }, frame)
  if open then r.defer(loop) end
end
loop()
