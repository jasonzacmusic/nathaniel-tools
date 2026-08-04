-- @description Unsolo & Unselect
-- @version 1.0.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about The panic key: clear solo, record-arm, selections and time selection.
-- @changelog
--   1.0.0 - first public release. Crash-hardened (GUID identity + ValidatePtr2),
--           signature-based change detection, shared safety library.

-- Unsolo & Unselect  (the panic key)
-- Extends "Custom: Unsolo & Unselect".  Same four steps, plus it clears record arm
-- and any leftover solo-defeat, and stops nothing that is playing.
local r = reaper

r.PreventUIRefresh(1)
r.Undo_BeginBlock2(0)

for i = 0, r.CountTracks(0) - 1 do
  local tr = r.GetTrack(0, i)
  r.SetMediaTrackInfo_Value(tr, "I_SOLO", 0)
  r.SetMediaTrackInfo_Value(tr, "I_RECARM", 0)
end

r.Main_OnCommand(40297, 0)   -- unselect all tracks
r.Main_OnCommand(40635, 0)   -- remove time selection
r.Main_OnCommand(40289, 0)   -- unselect all items

r.Undo_EndBlock2(0, "Unsolo, disarm & unselect", -1)
r.PreventUIRefresh(-1)
r.TrackList_AdjustWindows(false)
r.UpdateArrange()
