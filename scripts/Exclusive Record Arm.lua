-- @description Exclusive Record Arm (background: arming a track disarms the others; hold Option to add)
-- @version 1.2.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about
--   Runs quietly in the background.
--   Click a track's record-arm button: every other track is disarmed.
--   Hold Option while clicking: the track is added and nothing else changes.
--   Arming several tracks in one click (a selection) keeps all of them. Solo is left alone.
--   Run the action again to switch it off; its menu/toolbar state shows on while it runs.
--   Never touches inputs, monitoring, levels or the project file.
--   Option is read by the small helper Scripts/Nathaniel Tools/bin/nt_mods (source: tools/nt_mods.swift);
--   without it the script still works, just always exclusive.
-- @changelog
--   1.2.0 - Option-click adds instead of replacing. Solo back to normal (the 1.1 "Exclusive Arm and Solo" is retired).
--   1.0.0 - first version.

local r = reaper
local _, _, sec, cmd = r.get_action_context()
if r.set_action_options then r.set_action_options(1) end    -- running it again switches it off, no prompt

local MODS = r.GetResourcePath() .. "/Scripts/Nathaniel Tools/bin/nt_mods"
local HAVE_MODS = r.file_exists(MODS)
local function optionHeld()
  if not HAVE_MODS then return false end
  local out = r.ExecProcess('"' .. MODS .. '"', 500) or ""   -- "0\nalt cmd\n"; ~20 ms, only when something changed
  return out:find("alt", 1, true) ~= nil
end

local last, lastProj = {}, nil
local function snapshot(proj)
  local s = {}
  for i = 0, r.CountTracks(proj) - 1 do local tr = r.GetTrack(proj, i)
    s[r.GetTrackGUID(tr)] = r.GetMediaTrackInfo_Value(tr, "I_RECARM") == 1 end
  return s
end

local function loop()
  local proj = r.EnumProjects(-1)
  if proj ~= lastProj then last = snapshot(proj); lastProj = proj end
  local n = r.CountTracks(proj)
  local fresh, lost = {}, {}
  for i = 0, n - 1 do
    local tr = r.GetTrack(proj, i); local was = last[r.GetTrackGUID(tr)]
    local now = r.GetMediaTrackInfo_Value(tr, "I_RECARM") == 1
    if was ~= nil then
      if now and not was then fresh[tr] = true end
      if was and not now then lost[tr] = true end
    end
  end
  if next(fresh) then
    if optionHeld() then
      -- Option held: add, never replace. Put back anything switched off in the same click.
      for tr in pairs(lost) do r.SetMediaTrackInfo_Value(tr, "I_RECARM", 1) end
    else
      for i = 0, n - 1 do local tr = r.GetTrack(proj, i)
        if not fresh[tr] and r.GetMediaTrackInfo_Value(tr, "I_RECARM") == 1 then r.SetMediaTrackInfo_Value(tr, "I_RECARM", 0) end end
    end
  end
  last = snapshot(proj)
  r.defer(loop)
end

r.SetToggleCommandState(sec, cmd, 1); r.RefreshToolbar2(sec, cmd)
r.atexit(function() r.SetToggleCommandState(sec, cmd, 0); r.RefreshToolbar2(sec, cmd) end)
loop()
