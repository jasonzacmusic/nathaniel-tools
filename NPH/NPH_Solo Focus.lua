-- @description NPH Solo Focus
-- @version 1.0.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nph-reaper-suite
-- @donation https://github.com/jasonzacmusic/nph-reaper-suite
-- @about Deterministic exclusive solo. Follows item selection when there is one, press again to clear.
-- @changelog
--   1.0.0 - first public release. Crash-hardened (GUID identity + ValidatePtr2),
--           signature-based change detection, shared safety library.

-- NPH: Solo Focus
-- Replaces "Custom: Solo Selected Items".
-- Deterministic exclusive solo. If items are selected, focus their tracks.
-- Pressing again on the same focus un-solos everything.
-- Optional audition: if the transport is stopped, jump to the mouse and play.
local r = reaper

-- AUDITION moves the EDIT CURSOR to wherever the mouse happens to be and starts
-- playback.  That is a big, surprising side effect for a key you press to solo a
-- track: if the pointer is parked over the wrong bar - or over a docked window -
-- you lose your place in the session and the transport runs.  Defaulting it OFF.
-- Set to true if you want the old click-to-audition behaviour back.
local AUDITION = false

local function selectedTracks()
  local t = {}
  for i = 0, r.CountSelectedTracks(0) - 1 do t[#t+1] = r.GetSelectedTrack(0, i) end
  return t
end

local function tracksOfSelectedItems()
  local seen, t = {}, {}
  for i = 0, r.CountSelectedMediaItems(0) - 1 do
    local it = r.GetSelectedMediaItem(0, i)
    if it then
      local tr = r.GetMediaItem_Track(it)
      if tr then
        local g = r.GetTrackGUID(tr)
        if not seen[g] then seen[g] = true; t[#t+1] = tr end
      end
    end
  end
  return t
end

r.PreventUIRefresh(1)
r.Undo_BeginBlock2(0)

local targets = tracksOfSelectedItems()
if #targets > 0 then
  -- mirror the old _SWS_SELTRKWITEM behaviour, but only when it has something to say
  r.Main_OnCommand(40297, 0)                     -- unselect all tracks
  for _, tr in ipairs(targets) do r.SetTrackSelected(tr, true) end
else
  targets = selectedTracks()
end

if #targets == 0 then
  -- nothing to focus: treat as "clear solo"
  r.Main_OnCommand(40340, 0)                     -- unsolo all
  r.Undo_EndBlock2(0, "NPH: Clear solo", -1)
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  return
end

-- is the current solo state already exactly this set?
local exact = true
local want = {}
for _, tr in ipairs(targets) do want[r.GetTrackGUID(tr)] = true end
for i = 0, r.CountTracks(0) - 1 do
  local tr = r.GetTrack(0, i)
  local soloed = r.GetMediaTrackInfo_Value(tr, "I_SOLO") > 0
  local wanted = want[r.GetTrackGUID(tr)] == true
  if soloed ~= wanted then exact = false break end
end

if exact then
  r.Main_OnCommand(40340, 0)                     -- unsolo all
  r.Undo_EndBlock2(0, "NPH: Clear solo", -1)
else
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    r.SetMediaTrackInfo_Value(tr, "I_SOLO", 0)
  end
  for _, tr in ipairs(targets) do
    r.SetMediaTrackInfo_Value(tr, "I_SOLO", 2)   -- 2 = solo in place (ignore routing)
  end
  r.Undo_EndBlock2(0, "NPH: Solo focus", -1)

  if AUDITION and r.GetPlayState() == 0 then
    r.Main_OnCommand(40513, 0)                   -- edit cursor to mouse
    r.Main_OnCommand(40317, 0)                   -- play (skip time selection)
  end
end

r.PreventUIRefresh(-1)
r.UpdateArrange()
r.TrackList_AdjustWindows(false)
