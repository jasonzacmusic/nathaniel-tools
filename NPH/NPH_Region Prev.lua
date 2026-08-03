-- @description NPH Region Previous
-- @version 1.0.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nph-reaper-suite
-- @donation https://github.com/jasonzacmusic/nph-reaper-suite
-- @about Jump to the previous region, snapping to the current region's start first.
-- @changelog
--   1.0.0 - first public release. Crash-hardened (GUID identity + ValidatePtr2),
--           signature-based change detection, shared safety library.

-- NPH: Region Previous
local r = reaper
local EPS = 0.05   -- generous, so a press mid-region snaps to that region's start first

local playing = r.GetPlayState() & 1 == 1
local pos = playing and r.GetPlayPosition() or r.GetCursorPosition()

-- if we are inside a region and not right at its start, go to this region's start
local curS, curE
local best, bs, be
local i = 0
while true do
  local ok, isrgn, s, e, name = r.EnumProjectMarkers3(0, i)
  if ok == 0 then break end
  if isrgn then
    if s <= pos - EPS and e > pos then curS, curE = s, e end
    if s < pos - EPS then
      if not bs or s > bs then best, bs, be = name, s, e end
    end
  end
  i = i + 1
end

local ts, te
if curS and math.abs(pos - curS) > EPS then
  ts, te = curS, curE
elseif bs then
  ts, te = bs, be
else
  return
end

r.GetSet_LoopTimeRange2(0, true, false, ts, te, false)
r.SetEditCurPos2(0, ts, true, true)
if playing then r.Main_OnCommand(40317, 0) end
r.UpdateArrange()
