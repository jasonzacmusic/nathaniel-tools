-- @description NPH Marker at Bar
-- @version 1.0.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nph-reaper-suite
-- @donation https://github.com/jasonzacmusic/nph-reaper-suite
-- @about Insert a marker on the nearest true bar line, not the arrange grid.
-- @changelog
--   1.0.0 - first public release. Crash-hardened (GUID identity + ValidatePtr2),
--           signature-based change detection, shared safety library.

-- NPH: Marker at nearest BAR
-- Replaces "Custom: Marker NPH", which inserted at the raw edit cursor and then ran
-- _BR_CLOSEST_PROJ_MARKER_MOUSE_SNAP.  That snapped to the ARRANGE GRID (currently
-- 1/8 note), not the bar -- and worse, it could grab a DIFFERENT existing marker and
-- drag it to the mouse, silently destroying it.
--
-- This computes the true measure boundary with TimeMap_GetMeasureInfo (integer
-- measures, no float drift) and inserts there.  While playing it uses the play
-- cursor, so you can drop markers live.
local r = reaper

local MODE = "bar"   -- "bar" or "beat"

local playing = r.GetPlayState() & 1 == 1
local pos = playing and r.GetPlayPosition() or r.GetCursorPosition()

local function measureStartTime(m)
  local _, qnStart = r.TimeMap_GetMeasureInfo(0, m)
  return r.TimeMap2_QNToTime(0, qnStart), qnStart
end

local target
if MODE == "bar" then
  local _, measures = r.TimeMap2_timeToBeats(0, pos)      -- measures = 0-based bar index
  local t0 = measureStartTime(measures)
  local t1 = measureStartTime(measures + 1)
  target = (math.abs(pos - t0) <= math.abs(t1 - pos)) and t0 or t1
else
  local qn = r.TimeMap2_timeToQN(0, pos)
  target = r.TimeMap2_QNToTime(0, math.floor(qn + 0.5))
end

-- don't stack a duplicate marker on the same bar line
local i = 0
while true do
  local ok, isrgn, s = r.EnumProjectMarkers3(0, i)
  if ok == 0 then break end
  if (not isrgn) and math.abs(s - target) < 1e-6 then return end
  i = i + 1
end

r.Undo_BeginBlock2(0)
r.AddProjectMarker2(0, false, target, 0, "", -1, 0)
if not playing then r.SetEditCurPos2(0, target, false, false) end
r.Undo_EndBlock2(0, "NPH: Marker at nearest bar", -1)
r.UpdateArrange()
