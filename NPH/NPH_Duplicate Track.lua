-- @description NPH Duplicate Track
-- @version 1.0.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nph-reaper-suite
-- @donation https://github.com/jasonzacmusic/nph-reaper-suite
-- @about Duplicate tracks empty and armed, without disarming the rest of the session.
-- @changelog
--   1.0.0 - first public release. Crash-hardened (GUID identity + ValidatePtr2),
--           signature-based change detection, shared safety library.

-- NPH: Duplicate Track (empty)
-- Replaces "Custom: Duplicate Track".  Step 8 of the old chain was 40065
-- "Envelope: Clear or remove envelope", which only ever touched the ONE selected
-- envelope -- so duplicated tracks kept all their automation.
-- It also relied on 40771 (toggle ALL track grouping) netting out to its original
-- state, which only holds if grouping happened to start enabled.
--
-- Result: same FX, routing, name and colour; no items, no automation; armed and
-- ready to record.
local r = reaper

local sel = {}
for i = 0, r.CountSelectedTracks(0) - 1 do sel[#sel+1] = r.GetSelectedTrack(0, i) end
if #sel == 0 then return end

r.Undo_BeginBlock2(0)
r.PreventUIRefresh(1)

local grouping = r.GetToggleCommandState(40771) == 1
if grouping then r.Main_OnCommand(40771, 0) end                 -- suspend grouping

r.Main_OnCommand(r.NamedCommandLookup("_S&M_WNCLS5"), 0)        -- close floating FX for sel

-- FIX: this used to clear I_RECARM on EVERY track in the project and never put
-- it back.  The intent was only to stop the duplicate inheriting record-arm, but
-- the side effect was disarming the whole session - in a 452-track live rig that
-- silently destroys the record setup, and nothing tells you it happened.
-- Snapshot the arm state by GUID, disarm, then restore everything that was not
-- created by this script.
local armWas = {}
for i = 0, r.CountTracks(0) - 1 do
  local tr = r.GetTrack(0, i)
  if tr then
    armWas[r.GetTrackGUID(tr)] = r.GetMediaTrackInfo_Value(tr, "I_RECARM")
    r.SetMediaTrackInfo_Value(tr, "I_RECARM", 0)
  end
end

r.Main_OnCommand(40062, 0)                                      -- Track: Duplicate tracks

-- selection is now the duplicates
local dup = {}
for i = 0, r.CountSelectedTracks(0) - 1 do dup[#dup+1] = r.GetSelectedTrack(0, i) end

for _, tr in ipairs(dup) do
  if r.ValidatePtr2(0, tr, "MediaTrack*") then
    for i = r.CountTrackMediaItems(tr) - 1, 0, -1 do
      r.DeleteTrackMediaItem(tr, r.GetTrackMediaItem(tr, i))
    end
  end
end

r.Main_OnCommand(r.NamedCommandLookup("_S&M_REMOVE_ALLENVS"), 0)

-- put every pre-existing track back exactly as it was...
local isDup = {}
for _, tr in ipairs(dup) do
  if r.ValidatePtr2(0, tr, "MediaTrack*") then isDup[r.GetTrackGUID(tr)] = true end
end
for i = 0, r.CountTracks(0) - 1 do
  local tr = r.GetTrack(0, i)
  if tr then
    local g = r.GetTrackGUID(tr)
    if not isDup[g] and armWas[g] ~= nil then
      r.SetMediaTrackInfo_Value(tr, "I_RECARM", armWas[g])
    end
  end
end

-- ...and arm only the new duplicates, which is the point of the script
for _, tr in ipairs(dup) do
  if r.ValidatePtr2(0, tr, "MediaTrack*") then
    r.SetMediaTrackInfo_Value(tr, "I_RECARM", 1)
    r.SetMediaTrackInfo_Value(tr, "I_SOLO", 0)
    r.SetMediaTrackInfo_Value(tr, "B_MUTE", 0)
  end
end

if grouping then r.Main_OnCommand(40771, 0) end                 -- restore grouping

r.Main_OnCommand(r.NamedCommandLookup("_S&M_WNCLS3"), 0)
r.Main_OnCommand(r.NamedCommandLookup("_S&M_WNCLS4"), 0)

r.PreventUIRefresh(-1)
r.Undo_EndBlock2(0, "NPH: Duplicate track (empty, armed)", -1)
r.TrackList_AdjustWindows(false)
r.UpdateArrange()
