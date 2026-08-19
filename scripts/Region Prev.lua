-- @description Region Previous
-- @version 1.1.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about Jump to the previous region and make it the time selection. While playing, playback follows the jump (with smooth seek, on the bar).
-- @changelog
--   1.1.0 - no longer restarts playback with "Play (skip time selection)", which skipped the very region it had just selected.
--   1.0.0 - first public release.

-- Region Previous
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
-- While playing, SetEditCurPos2(seekplay=true) already moves playback (smooth
-- seek lands it on the bar). 40317 "Play (skip time selection)" used to be
-- called here and skipped the very region we had just selected.
r.UpdateArrange()
