-- @description NPH FX Float Toggle
-- @version 1.0.0
-- @author Jason Zac
-- @link https://daw.nathanielschool.com
-- @donation https://daw.nathanielschool.com/donate
-- @about True XOR float of FX #1 on the selected tracks.
-- @changelog
--   1.0.0 - first public release. Crash-hardened (GUID identity + ValidatePtr2),
--           signature-based change detection, shared safety library.

-- NPH: FX Float Toggle  (true XOR float, FX #1)
-- Replaces "Custom: XOR Float FX", which targeted the LAST TOUCHED track and
-- could only ever open (it closed everything first, then toggled).
-- This follows the track SELECTION and genuinely toggles.
local r = reaper

local sel = {}
for i = 0, r.CountSelectedTracks(0) - 1 do sel[#sel+1] = r.GetSelectedTrack(0, i) end
if #sel == 0 then return end

local function anyFloating(tracks)
  for _, tr in ipairs(tracks) do
    if r.TrackFX_GetCount(tr) > 0 and r.TrackFX_GetFloatingWindow(tr, 0) then
      return true
    end
  end
  return false
end

r.PreventUIRefresh(1)

if anyFloating(sel) then
  -- close FX #1 on the selected tracks
  for _, tr in ipairs(sel) do
    if r.TrackFX_GetCount(tr) > 0 then r.TrackFX_Show(tr, 0, 2) end
  end
else
  -- exclusive: close every floating FX window anywhere, then open FX #1 here
  r.Main_OnCommand(r.NamedCommandLookup("_S&M_WNCLS3"), 0)
  for _, tr in ipairs(sel) do
    if r.TrackFX_GetCount(tr) > 0 then r.TrackFX_Show(tr, 0, 3) end
  end
end

r.PreventUIRefresh(-1)
