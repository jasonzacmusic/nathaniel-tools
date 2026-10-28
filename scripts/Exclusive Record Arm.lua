-- @description Exclusive Record Arm (background: arming a track disarms every other track)
-- @version 1.0.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about
--   Runs quietly in the background. Click the record-arm button on any track and every other
--   track in the project is disarmed, so only the track you just touched records. Arming several
--   tracks in one click (a selection) keeps all of them. Run the action again to switch it off;
--   its toolbar/menu state shows on while it runs. Never touches inputs, monitoring or levels.
-- @changelog
--   1.0.0 - first version.

local r = reaper
local _, _, sec, cmd = r.get_action_context()
local last = {}       -- track GUID -> armed last cycle
local lastProj = nil

local function snapshot(proj)
  local s = {}
  for i = 0, r.CountTracks(proj) - 1 do
    local tr = r.GetTrack(proj, i)
    s[r.GetTrackGUID(tr)] = r.GetMediaTrackInfo_Value(tr, "I_RECARM") == 1
  end
  return s
end

local function loop()
  local proj = r.EnumProjects(-1)
  if proj ~= lastProj then last = snapshot(proj); lastProj = proj end
  local fresh = {}
  local n = r.CountTracks(proj)
  for i = 0, n - 1 do
    local tr = r.GetTrack(proj, i)
    if r.GetMediaTrackInfo_Value(tr, "I_RECARM") == 1 and not last[r.GetTrackGUID(tr)] then fresh[tr] = true end
  end
  if next(fresh) then
    for i = 0, n - 1 do
      local tr = r.GetTrack(proj, i)
      if not fresh[tr] and r.GetMediaTrackInfo_Value(tr, "I_RECARM") == 1 then
        r.SetMediaTrackInfo_Value(tr, "I_RECARM", 0)
      end
    end
  end
  last = snapshot(proj)
  r.defer(loop)
end

r.SetToggleCommandState(sec, cmd, 1); r.RefreshToolbar2(sec, cmd)
r.atexit(function() r.SetToggleCommandState(sec, cmd, 0); r.RefreshToolbar2(sec, cmd) end)
loop()
