-- @description Region Next
-- @version 1.1.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about Jump to the next region and make it the time selection. While playing, playback follows the jump (with smooth seek, on the bar).
-- @changelog
--   1.1.0 - no longer restarts playback with "Play (skip time selection)", which skipped the very region it had just selected.
--   1.0.0 - first public release.

-- Region Next
-- Replaces "Custom: Region Switch", whose step 2 TOGGLED a global REAPER
-- preference on every press, so it behaved differently every other time.
local r = reaper
local EPS = 1e-6

local playing = r.GetPlayState() & 1 == 1
local pos = playing and r.GetPlayPosition() or r.GetCursorPosition()

local best, bs, be
local i = 0
while true do
  local ok, isrgn, s, e, name, idx = r.EnumProjectMarkers3(0, i)
  if ok == 0 then break end
  if isrgn and s > pos + EPS then
    if not best or s < bs then best, bs, be = name, s, e end
  end
  i = i + 1
end

if not best then return end

r.GetSet_LoopTimeRange2(0, true, false, bs, be, false)
r.SetEditCurPos2(0, bs, true, true)
-- While playing, SetEditCurPos2(seekplay=true) already moves playback (smooth
-- seek lands it on the bar). 40317 "Play (skip time selection)" used to be
-- called here and skipped the very region we had just selected.
r.UpdateArrange()
