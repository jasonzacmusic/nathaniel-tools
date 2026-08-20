-- Usage: bind this ReaScript to absolute MIDI CC20 from "12 Step Bridge".
-- Knob 7 pans every record-armed track without changing track selection.
-- Companion to NSM_Set_Armed_Tracks_Volume.lua, same shape, same contract.

local function incoming_cc_value()
  local _, _, _, _, _, _, value = reaper.get_action_context()
  if type(value) ~= "number" or value < 0 then return nil end
  return math.max(0, math.min(127, value))
end

-- Centre-detented: the middle of the knob's throw is dead centre, not a
-- fraction off it.
local function midi_cc_to_pan(value)
  if math.abs(value - 64) <= 1 then return 0 end
  return math.max(-1, math.min(1, (value - 64) / 63))
end

local value = incoming_cc_value()
if not value then return end

local pan = midi_cc_to_pan(value)
local changed = false

reaper.PreventUIRefresh(1)
for index = 0, reaper.CountTracks(0) - 1 do
  local track = reaper.GetTrack(0, index)
  if track and reaper.GetMediaTrackInfo_Value(track, "I_RECARM") > 0 then
    reaper.SetMediaTrackInfo_Value(track, "D_PAN", pan)
    changed = true
  end
end
reaper.PreventUIRefresh(-1)

if changed then
  reaper.TrackList_AdjustWindows(false)
  reaper.UpdateArrange()
end
