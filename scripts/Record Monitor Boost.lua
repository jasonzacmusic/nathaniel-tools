-- @description Record Monitor Boost (background: the track you are recording plays louder in your ears while you record; the file is untouched)
-- @version 1.0.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about
--   Runs quietly in the background.
--   A horn or voice in the room drowns its own headphone feed, so while you record it sounds soft.
--   While REAPER is recording, every armed track that records its input is turned up (6 dB by default)
--   so you hear yourself properly. The moment recording stops, the fader goes back exactly where it was.
--   The recorded file is not affected: those tracks record the input, before the fader.
--   Move the fader during a take and that move is kept (minus the boost) when recording stops.
--   Change the amount: Extended state "NathanielTools" / "RecordMonitorBoostDB" (0 switches the boost off).
--   Run the action again to switch it off; its menu/toolbar state shows on while it runs.
-- @changelog
--   1.0.0 - first version.

local r = reaper
local _, _, sec, cmd = r.get_action_context()
if r.set_action_options then r.set_action_options(1) end

local KEY = "P_EXT:nt_monboost_orig"   -- the fader before the boost, kept on the track so a crash can be undone
local MAXVOL = 3.981                    -- +12 dB, the top of REAPER's fader

local function boostDB()
  local v = tonumber(r.GetExtState("NathanielTools", "RecordMonitorBoostDB"))
  return v or 6
end

local boosted = {}   -- [track] = {proj, orig, set}

local function restore(tr, b)
  if r.ValidatePtr2(b.proj, tr, "MediaTrack*") then
    r.SetMediaTrackInfo_Value(tr, "D_VOL", b.orig)
    r.GetSetMediaTrackInfo_String(tr, KEY, "", true)
  end
  boosted[tr] = nil
end

-- a fader left boosted by a crash or a force-quit goes back on the next start
local function sweepLeftovers()
  for pi = 0, 99 do
    local proj = r.EnumProjects(pi); if not proj then break end
    for i = 0, r.CountTracks(proj) - 1 do
      local tr = r.GetTrack(proj, i)
      local ok, v = r.GetSetMediaTrackInfo_String(tr, KEY, "", false)
      if ok and tonumber(v) then
        r.SetMediaTrackInfo_Value(tr, "D_VOL", tonumber(v))
        r.GetSetMediaTrackInfo_String(tr, KEY, "", true)
      end
    end
  end
end

local function wants(tr)
  return r.GetMediaTrackInfo_Value(tr, "I_RECARM") == 1
     and r.GetMediaTrackInfo_Value(tr, "I_RECMON") > 0
     and r.GetMediaTrackInfo_Value(tr, "I_RECMODE") == 0      -- records the input, so the fader never reaches the file
end

local function loop()
  local proj = r.EnumProjects(-1)
  local recording = (r.GetPlayStateEx(proj) & 4) == 4
  local db = boostDB()

  for tr, b in pairs(boosted) do
    if not recording or b.proj ~= proj or not r.ValidatePtr2(b.proj, tr, "MediaTrack*") or not wants(tr) then
      restore(tr, b)
    else
      local now = r.GetMediaTrackInfo_Value(tr, "D_VOL")
      if math.abs(now - b.set) > 1e-6 then                   -- he moved the fader mid-take: keep his move
        b.orig = now / b.factor; b.set = now
        r.GetSetMediaTrackInfo_String(tr, KEY, tostring(b.orig), true)
      end
    end
  end

  if recording and db > 0 then
    local factor = 10 ^ (db / 20)
    for i = 0, r.CountTracks(proj) - 1 do
      local tr = r.GetTrack(proj, i)
      local orig = r.GetMediaTrackInfo_Value(tr, "D_VOL")
      if not boosted[tr] and orig > 0.0001 and wants(tr) then   -- a fader pulled all the way down stays down
        local set = math.min(orig * factor, MAXVOL)
        r.GetSetMediaTrackInfo_String(tr, KEY, tostring(orig), true)
        r.SetMediaTrackInfo_Value(tr, "D_VOL", set)
        boosted[tr] = { proj = proj, orig = orig, set = set, factor = set / math.max(orig, 1e-9) }
      end
    end
  end

  r.defer(loop)
end

sweepLeftovers()
r.SetToggleCommandState(sec, cmd, 1); r.RefreshToolbar2(sec, cmd)
r.atexit(function()
  for tr, b in pairs(boosted) do restore(tr, b) end
  r.SetToggleCommandState(sec, cmd, 0); r.RefreshToolbar2(sec, cmd)
end)
loop()
