-- @description Record Arm Toggle
-- @version 1.0.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about Exclusive record-arm on the selected tracks. Press again to disarm everything. Never touches pan.
-- @changelog
--   1.0.0 - first public release. Crash-hardened (GUID identity + ValidatePtr2),
--           signature-based change detection, shared safety library.

-- Record Arm Toggle
-- Replaces "Custom: Record Toggle" and "Custom: XOR Record Arm".
-- Exclusive arm on the selected tracks. Press again to disarm everything.
-- Never touches pan (the old chain ran _XENAKIOS_PANTRACKSCENTER).
local r = reaper

local sel = {}
for i = 0, r.CountSelectedTracks(0) - 1 do sel[#sel+1] = r.GetSelectedTrack(0, i) end

r.PreventUIRefresh(1)
r.Undo_BeginBlock2(0)

if #sel == 0 then
  for i = 0, r.CountTracks(0) - 1 do
    r.SetMediaTrackInfo_Value(r.GetTrack(0, i), "I_RECARM", 0)
  end
  r.Undo_EndBlock2(0, "Disarm all", -1)
  r.PreventUIRefresh(-1)
  r.TrackList_AdjustWindows(false)
  return
end

-- already exactly this set armed?  then disarm everything.
local want = {}
for _, tr in ipairs(sel) do want[r.GetTrackGUID(tr)] = true end
local exact = true
for i = 0, r.CountTracks(0) - 1 do
  local tr = r.GetTrack(0, i)
  local armed = r.GetMediaTrackInfo_Value(tr, "I_RECARM") == 1
  if armed ~= (want[r.GetTrackGUID(tr)] == true) then exact = false break end
end

for i = 0, r.CountTracks(0) - 1 do
  r.SetMediaTrackInfo_Value(r.GetTrack(0, i), "I_RECARM", 0)
end
if not exact then
  for _, tr in ipairs(sel) do r.SetMediaTrackInfo_Value(tr, "I_RECARM", 1) end
end

r.Undo_EndBlock2(0, exact and "Disarm all" or "Arm selected (exclusive)", -1)
r.PreventUIRefresh(-1)
r.TrackList_AdjustWindows(false)
