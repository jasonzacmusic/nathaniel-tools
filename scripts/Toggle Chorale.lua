-- @description Toggle Chorale (live vocal harmony)
-- @version 1.0.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about
--   Finds Chorale wherever it is in the project and flips it on/off.
--   Bind this to a footswitch and you have hands-free harmony.

--[[
  Toggle Chorale
  ----------------------------------------------------------------------------
  One button. Finds the Chorale plugin on whatever track it lives on and
  toggles it, so you do not have to have the right track selected, and it keeps
  working if you reorder the session.

  BIND IT TO YOUR FOOT CONTROLLER:
    Actions > Show action list > find "Toggle Chorale" > Add...  > press the
    pedal. Any MIDI pedal works - the 12 Step, the Keith McMillan, a sustain
    switch. REAPER learns whatever it sees.

  It flashes the state in the transport bar so you can confirm mid-song without
  looking at a plugin window.
--]]

local r = reaper

local function findChorale()
  local proj = r.EnumProjects(-1)
  local n = r.CountTracks(proj)
  for i = 0, n - 1 do
    local t = r.GetTrack(proj, i)
    if t then
      for fx = 0, r.TrackFX_GetCount(t) - 1 do
        local _, nm = r.TrackFX_GetFXName(t, fx, "")
        if nm and nm:lower():find("chorale", 1, true) then return t, fx, nm end
      end
    end
  end
  -- also look on the master, in case it is used as a global effect
  local m = r.GetMasterTrack(proj)
  if m then
    for fx = 0, r.TrackFX_GetCount(m) - 1 do
      local _, nm = r.TrackFX_GetFXName(m, fx, "")
      if nm and nm:lower():find("chorale", 1, true) then return m, fx, nm end
    end
  end
  return nil
end

local track, fx = findChorale()

if not track then
  r.MB("Chorale is not loaded in this project.\n\n" ..
       "Put it on your vocal track, then this button will find it wherever it is.",
       "Toggle Chorale", 0)
  return
end

local on = not r.TrackFX_GetEnabled(track, fx)
r.TrackFX_SetEnabled(track, fx, on)

-- tell you, without needing a plugin window open
local _, tn = r.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
r.Help_Set(("CHORALE %s   (%s)"):format(on and "ON  - harmony live" or "OFF - dry vocal",
                                        (tn ~= "" and tn) or "master"), false)
