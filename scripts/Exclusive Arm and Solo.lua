-- @description Exclusive Arm and Solo (background: arming or soloing a track clears the others; hold Option to add)
-- @version 1.1.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about
--   Runs quietly in the background.
--   Click a track's record-arm button: every other track is disarmed.
--   Click a track's solo button: every other track is unsoloed.
--   Hold Option while clicking: the track is added and nothing else changes.
--   Arming or soloing several tracks in one click (a selection) keeps all of them.
--   Run the action again to switch it off; its menu/toolbar state shows on while it runs.
--   Never touches inputs, monitoring, levels or the project file.
--   Option is read by the small helper Scripts/Nathaniel Tools/bin/nt_mods (source: tools/nt_mods.swift);
--   without it the script still works, just always exclusive.
-- @changelog
--   1.1.0 - solo works the same way as record arm; Option-click adds instead of replacing.
--           Replaces "Exclusive Record Arm" 1.0.0.

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
local function read(tr)
  return { arm = r.GetMediaTrackInfo_Value(tr, "I_RECARM") == 1,
           solo = r.GetMediaTrackInfo_Value(tr, "I_SOLO") > 0,
           soloV = r.GetMediaTrackInfo_Value(tr, "I_SOLO"),
           defeat = r.GetMediaTrackInfo_Value(tr, "B_SOLO_DEFEAT") == 1 }
end
local function snapshot(proj)
  local s = {}
  for i = 0, r.CountTracks(proj) - 1 do local tr = r.GetTrack(proj, i); s[r.GetTrackGUID(tr)] = read(tr) end
  return s
end
local function soloValue(proj, except)
  for i = 0, r.CountTracks(proj) - 1 do local tr = r.GetTrack(proj, i)
    if not except[tr] then local v = r.GetMediaTrackInfo_Value(tr, "I_SOLO") if v > 0 then return v end end end
  return 2                                                     -- solo in place, REAPER's default
end

local function loop()
  local proj = r.EnumProjects(-1)
  if proj ~= lastProj then last = snapshot(proj); lastProj = proj end
  local n = r.CountTracks(proj)
  local newArm, newSolo, newDefeat = {}, {}, {}
  local lostArm, lostSolo = {}, {}
  local any = false
  for i = 0, n - 1 do
    local tr = r.GetTrack(proj, i); local now = read(tr); local was = last[r.GetTrackGUID(tr)]
    if was then
      if now.arm and not was.arm then newArm[tr] = true; any = true end
      if now.solo and not was.solo then newSolo[tr] = true; any = true end
      if now.defeat and not was.defeat then newDefeat[tr] = true; any = true end
      if was.arm and not now.arm then lostArm[tr] = true end
      if was.solo and not now.solo then lostSolo[tr] = was.soloV end
    end
  end
  if any then
    local add = optionHeld()
    if add then
      -- Option held: add, never replace. Put back anything REAPER switched off in the same click.
      if next(newArm) then for tr in pairs(lostArm) do r.SetMediaTrackInfo_Value(tr, "I_RECARM", 1) end end
      if next(newSolo) or next(newDefeat) then for tr, v in pairs(lostSolo) do r.SetMediaTrackInfo_Value(tr, "I_SOLO", v) end end
      -- REAPER's own Option-click on solo is "solo defeat": turn that into an added solo instead
      for tr in pairs(newDefeat) do
        r.SetMediaTrackInfo_Value(tr, "B_SOLO_DEFEAT", 0)
        r.SetMediaTrackInfo_Value(tr, "I_SOLO", soloValue(proj, newDefeat))
      end
    else
      if next(newArm) then
        for i = 0, n - 1 do local tr = r.GetTrack(proj, i)
          if not newArm[tr] and r.GetMediaTrackInfo_Value(tr, "I_RECARM") == 1 then r.SetMediaTrackInfo_Value(tr, "I_RECARM", 0) end end
      end
      if next(newSolo) then
        for i = 0, n - 1 do local tr = r.GetTrack(proj, i)
          if not newSolo[tr] and r.GetMediaTrackInfo_Value(tr, "I_SOLO") > 0 then r.SetMediaTrackInfo_Value(tr, "I_SOLO", 0) end end
      end
    end
  end
  last = snapshot(proj)
  r.defer(loop)
end

r.SetToggleCommandState(sec, cmd, 1); r.RefreshToolbar2(sec, cmd)
r.atexit(function() r.SetToggleCommandState(sec, cmd, 0); r.RefreshToolbar2(sec, cmd) end)
loop()
