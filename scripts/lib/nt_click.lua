-- @noindex
-- Shared library for the Nathaniel Tools. Not a standalone action.
-- Distributed by the "Shared Libraries" package via its @provides tag.

--[[
  nt_click — the shared brain behind the two click surfaces.

  "Click Bar"    lives in the toolbar row: time signatures, pre-roll, splits.
  "Click Levels" lives in the docker: the two beat faders and the accent grid.

  Everything that both of them need to know about REAPER's metronome lives
  here, once.

  Author: Jason Zac / Nathaniel School of Music
--]]

local r = reaper
local M = {}

--------------------------------------------------------------------------------
-- actions
--------------------------------------------------------------------------------
M.METRONOME = 40364  -- Options: Toggle metronome
M.PREROLL   = 41819  -- Pre-roll: Toggle pre-roll on record
M.SETTINGS  = 40363  -- Options: Show metronome/pre-roll settings

function M.isOn(command) return r.GetToggleCommandState(command) == 1 end
function M.fire(command) r.Main_OnCommand(command, 0) end

--------------------------------------------------------------------------------
-- levels
--------------------------------------------------------------------------------
M.MIN_DB, M.MAX_DB = -60.0, 6.0
M.DEFAULT_DB = { -12.0, -20.0 }

function M.clampDb(db) return math.max(M.MIN_DB, math.min(M.MAX_DB, db)) end

function M.gainToDb(gain)
  if gain <= 0.0000001 then return M.MIN_DB end
  return 20 * math.log(gain, 10)
end
function M.dbToGain(db)
  if db <= M.MIN_DB then return 0 end
  return 10 ^ (db / 20)
end

-- Fader taper. A straight dB scale would spend half the travel below -27 dB,
-- where nothing useful lives. Squaring it puts -24..+6 dB - the only part you
-- ever set a click in - across most of the bar.
function M.positionToDb(position)
  position = math.max(0, math.min(1, position))
  return M.clampDb(M.MAX_DB - ((1 - position) ^ 2) * (M.MAX_DB - M.MIN_DB))
end
function M.dbToPosition(db)
  local span = (M.MAX_DB - M.clampDb(db)) / (M.MAX_DB - M.MIN_DB)
  return math.max(0, math.min(1, 1 - math.sqrt(span)))
end

function M.readDb(key, fallback)
  return M.clampDb(M.gainToDb(r.SNM_GetDoubleConfigVar(key, M.dbToGain(fallback))))
end
function M.writeDb(key, db)
  r.SNM_SetDoubleConfigVar(key, M.dbToGain(M.clampDb(db)))
end

--------------------------------------------------------------------------------
-- pre-roll
--------------------------------------------------------------------------------
-- Kept as a real number, so half and quarter bars are allowed: 0.5 and 0.25 are
-- how you count a pickup in.
function M.prerollBars()
  return r.SNM_GetDoubleConfigVar("prerollmeas", 2)
end
function M.setPrerollBars(value)
  r.SNM_SetDoubleConfigVar("prerollmeas", math.max(0.125, math.min(64, value)))
end
function M.formatBars(value)
  if math.abs(value - math.floor(value + 0.5)) < 0.001 then
    return string.format("%d", math.floor(value + 0.5))
  end
  return (string.format("%.3f", value):gsub("0+$", ""):gsub("%.$", ""))
end

--------------------------------------------------------------------------------
-- meter
--------------------------------------------------------------------------------
-- "7+6", "3-3-3-3-4", "3 3 2", "13", "2+2+3/4" all mean something.
function M.parseGroups(text)
  local body, den = text:match("^(.-)%s*/%s*(%d+)%s*$")
  body = body or text
  den = tonumber(den) or 8
  local groups = {}
  for piece in body:gmatch("[^%+%-,%s]+") do
    local n = tonumber(piece)
    if n and n >= 1 then groups[#groups + 1] = math.floor(n) end
  end
  if #groups == 0 then return nil, nil end
  return groups, den
end

function M.total(groups)
  local sum = 0
  for _, count in ipairs(groups) do sum = sum + count end
  return sum
end

-- Which bar is the cursor in, and where does it start.
function M.cursorMeasure()
  local pos = r.GetCursorPosition()
  local _, measures = r.TimeMap2_timeToBeats(0, pos)
  return measures, r.TimeMap2_beatsToTime(0, 0, measures)
end

function M.meterAtCursor()
  local num, den = r.TimeMap_GetTimeSigAtTime(0, r.GetCursorPosition())
  return math.floor((num or 4) + 0.5), math.floor((den or 4) + 0.5)
end

-- Put a time signature on a bar. Always lands on the bar line, whatever the
-- cursor is sitting on - a time signature in the middle of a bar is not a
-- thing a musician means.
function M.setMeterAtMeasure(measure, num, den)
  local measureStart = r.TimeMap2_beatsToTime(0, 0, measure)
  local bpm = r.TimeMap2_GetDividedBpmAtTime(0, measureStart)
  if not bpm or bpm <= 0 then bpm = r.Master_GetTempo() end

  local existing = r.FindTempoTimeSigMarker(0, measureStart + 0.0001)
  if existing and existing >= 0 then
    local ok, markerPos = r.GetTempoTimeSigMarker(0, existing)
    if ok and math.abs(markerPos - measureStart) < 0.001 then
      return r.SetTempoTimeSigMarker(0, existing, -1, measure, 0, bpm, num, den, false)
    end
  end
  return r.SetTempoTimeSigMarker(0, -1, -1, measure, 0, bpm, num, den, false)
end

function M.setMeter(num, den)
  local measure = M.cursorMeasure()
  r.Undo_BeginBlock()
  M.setMeterAtMeasure(measure, num, den)
  r.Undo_EndBlock(string.format("Set meter %d/%d", num, den), -1)
  r.UpdateTimeline()
end

-- Break this bar into two: 15/8 becomes 7/8 then 8/8. The second half lands on
-- the next bar, and the bar after that goes back to what was there before, so
-- the split is exactly two bars long and nothing downstream shifts meaning.
function M.splitMeter(first, second, den)
  local measure = M.cursorMeasure()
  local num, oldDen = M.meterAtCursor()
  r.Undo_BeginBlock()
  M.setMeterAtMeasure(measure, first, den)
  M.setMeterAtMeasure(measure + 1, second, den)
  M.setMeterAtMeasure(measure + 2, num, oldDen)
  r.Undo_EndBlock(string.format("Split into %d/%d + %d/%d", first, den, second, den), -1)
  r.UpdateTimeline()
end

--------------------------------------------------------------------------------
-- accents
--------------------------------------------------------------------------------
-- REAPER's click pattern is per time-signature marker, and it IS scriptable:
-- TimeMap_GetMetronomePattern reads it, and passing "SET:<pattern>" writes it.
-- The letters are beat types as shown in REAPER's own pattern editor - A is the
-- accented beat, B an ordinary one (C and D are the two extra click sounds).
function M.patternFromGroups(groups)
  local beats = {}
  for _, count in ipairs(groups) do
    for beat = 1, count do beats[#beats + 1] = (beat == 1) end
  end
  return beats
end

function M.patternString(beats)
  local out = {}
  for _, accented in ipairs(beats) do out[#out + 1] = accented and "A" or "B" end
  return table.concat(out)
end

-- The pattern REAPER is actually using at the cursor, as a list of "is this
-- beat accented" flags. nil when REAPER will not say.
function M.readPattern()
  local _, measureStart = M.cursorMeasure()
  local ok, retval, text = pcall(r.TimeMap_GetMetronomePattern, 0, measureStart, "EXTENDED")
  if not ok or type(text) ~= "string" or text == "" then
    ok, retval, text = pcall(r.TimeMap_GetMetronomePattern, 0, measureStart, "")
  end
  if not ok or type(text) ~= "string" or text == "" then return nil end
  local beats = {}
  for i = 1, #text do
    local ch = text:sub(i, i)
    -- "EXTENDED" gives A/B/C/D; the compatibility form gives 1 for a primary
    -- beat and 2 for the rest.
    beats[#beats + 1] = (ch == "A" or ch == "1")
  end
  return beats, text
end

-- Write it. Returns true when REAPER took it.
function M.writePattern(beats)
  local text = M.patternString(beats)
  local _, measureStart = M.cursorMeasure()
  r.Undo_BeginBlock()
  local ok, retval = pcall(r.TimeMap_GetMetronomePattern, 0, measureStart, "SET:" .. text)
  r.Undo_EndBlock("Set click accents " .. text, -1)
  r.UpdateTimeline()
  return ok and retval ~= nil and retval ~= 0, text
end

-- Groups implied by which beats are accented: ABBABBAB -> 3+3+2.
function M.groupsFromPattern(beats)
  local groups, run = {}, 0
  for _, accented in ipairs(beats) do
    if accented and run > 0 then groups[#groups + 1] = run; run = 0 end
    run = run + 1
  end
  if run > 0 then groups[#groups + 1] = run end
  return groups
end

--------------------------------------------------------------------------------
-- the Korg
--------------------------------------------------------------------------------
-- 12 Step Bridge leaves the nanoKONTROL's click moves in this file. Its profile
-- is untouched; this is only the last few inches, because REAPER has no action
-- those controls could be learned to.
M.MAILBOX = r.GetResourcePath() .. "/nt_click_mailbox.txt"

function M.newMailbox()
  return { sequence = nil, seenAt = 0 }
end

-- Returns key, value when something new arrived.
function M.readMailbox(state)
  local fh = io.open(M.MAILBOX, "r")
  if not fh then return nil end
  local line = fh:read("*l")
  fh:close()
  if not line then return nil end
  local sequence, key, value = line:match("^(%d+)%s+(%S+)%s+(.+)$")
  if not sequence or sequence == state.sequence then return nil end
  state.sequence = sequence
  state.seenAt = r.time_precise()
  return key, value
end

function M.applyMailbox(key, value)
  if key == "beat1gain" or key == "beat2gain" then
    local gain = tonumber(value)
    if gain then r.SNM_SetDoubleConfigVar(key == "beat1gain" and "projmetrov1" or "projmetrov2", gain) end
  elseif key == "beat1" or key == "beat2" then
    local cc = tonumber(value)
    if cc then M.writeDb(key == "beat1" and "projmetrov1" or "projmetrov2", M.positionToDb(cc / 127)) end
  elseif key == "accents" then
    -- "ABBABBAB" or a grouping like 3+3+2
    local beats
    if value:match("^[ABCD12]+$") then
      beats = {}
      for i = 1, #value do
        local ch = value:sub(i, i)
        beats[i] = (ch == "A" or ch == "1")
      end
    else
      local groups = M.parseGroups(value)
      if groups then beats = M.patternFromGroups(groups) end
    end
    if beats then
      local ok, text = M.writePattern(beats)
      local fh = io.open(r.GetResourcePath() .. "/nt_click_strip_error.log", "a")
      if fh then
        local back = M.readPattern()
        fh:write(os.date("%H:%M:%S ") .. string.format("accents SET:%s -> taken=%s, REAPER now reports %s\n",
          text, tostring(ok), back and M.patternString(back) or "nothing"))
        fh:close()
      end
    end
  elseif key == "metronome" then M.fire(M.METRONOME)
  elseif key == "preroll" then M.fire(M.PREROLL)
  elseif key == "settings" then M.fire(M.SETTINGS)
  end
end

return M
