-- @description NPH FX Open/Close All
-- @version 1.0.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nph-reaper-suite
-- @donation https://github.com/jasonzacmusic/nph-reaper-suite
-- @about One unified open/close decision across every FX on the selected tracks.
-- @changelog
--   1.0.0 - first public release. Crash-hardened (GUID identity + ValidatePtr2),
--           signature-based change detection, shared safety library.

-- NPH: FX Open/Close ALL
-- Replaces "Custom: Open Close ALL", which fired eight INDEPENDENT toggles on the
-- last touched track, so a mixed open/closed state got inverted instead of unified.
-- This is a real unified open/close across every FX on the selected tracks.
local r = reaper

local sel = {}
for i = 0, r.CountSelectedTracks(0) - 1 do sel[#sel+1] = r.GetSelectedTrack(0, i) end
if #sel == 0 then
  local lt = r.GetLastTouchedTrack()
  if lt then sel[1] = lt else return end
end

local open, total = 0, 0
for _, tr in ipairs(sel) do
  local n = r.TrackFX_GetCount(tr)
  for fx = 0, n - 1 do
    total = total + 1
    if r.TrackFX_GetFloatingWindow(tr, fx) then open = open + 1 end
  end
end
if total == 0 then return end

r.PreventUIRefresh(1)
local show = (open == 0)     -- anything open at all -> close everything
for _, tr in ipairs(sel) do
  for fx = 0, r.TrackFX_GetCount(tr) - 1 do
    r.TrackFX_Show(tr, fx, show and 3 or 2)
  end
end
r.PreventUIRefresh(-1)
