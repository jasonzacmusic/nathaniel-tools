-- @description NPH Region Next
-- @version 1.0.0
-- @author Jason Zac
-- @link https://daw.nathanielschool.com
-- @donation https://daw.nathanielschool.com/donate
-- @about Jump to the next region without flipping any global preference.
-- @changelog
--   1.0.0 - first public release. Crash-hardened (GUID identity + ValidatePtr2),
--           signature-based change detection, shared safety library.

-- NPH: Region Next
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
if playing then r.Main_OnCommand(40317, 0) end   -- play (skip time selection)
r.UpdateArrange()
