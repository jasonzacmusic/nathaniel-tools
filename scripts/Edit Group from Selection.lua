-- @description Edit Group from Selection (media edits move together, nothing else)
-- @version 1.0.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about
--   Puts the selected tracks into one track group for EDITING ONLY: media and
--   razor edits on one track happen on all of them (split, trim, move, delete),
--   while faders, mutes, solos and arms stay independent. Press it again on the
--   same tracks to take them OUT of their edit group.
--   The clutch: "Track: Toggle all track grouping enabled" (Jason: Cmd+Shift+G)
--   bypasses every group while you do fine edits; press again to re-engage.
-- @changelog
--   1.0.0 - first version.

local r = reaper
local n = r.CountSelectedTracks(0)
if n < 2 then r.ShowMessageBox("Select two or more tracks first.", "Edit Group", 0) return end
local sel = {}
for i = 0, n - 1 do sel[#sel + 1] = r.GetSelectedTrack(0, i) end

local function lead(t)   return r.GetSetTrackGroupMembership(t, "MEDIA_EDIT_LEAD", 0, 0) end
local function follow(t) return r.GetSetTrackGroupMembership(t, "MEDIA_EDIT_FOLLOW", 0, 0) end
local function high(t)   return (r.GetSetTrackGroupMembershipHigh and r.GetSetTrackGroupMembershipHigh(t, "MEDIA_EDIT_LEAD", 0, 0)) or 0 end

-- already one edit group (all selected share a lead bit and nothing else has it)? -> ungroup
local common = 0xFFFFFFFF
for _, t in ipairs(sel) do common = common & lead(t) & follow(t) end
local bit = nil
if common ~= 0 then for b = 0, 31 do if common & (1 << b) ~= 0 then bit = 1 << b break end end end
r.Undo_BeginBlock2(0)
if bit then
  local others = false
  for i = 0, r.CountTracks(0) - 1 do
    local t = r.GetTrack(0, i)
    local inSel = false
    for _, s in ipairs(sel) do if s == t then inSel = true end end
    if not inSel and (lead(t) & bit ~= 0 or follow(t) & bit ~= 0) then others = true end
  end
  if not others then
    for _, t in ipairs(sel) do
      r.GetSetTrackGroupMembership(t, "MEDIA_EDIT_LEAD", bit, 0)
      r.GetSetTrackGroupMembership(t, "MEDIA_EDIT_FOLLOW", bit, 0)
    end
    r.Undo_EndBlock2(0, "Edit group: ungroup selected tracks", -1)
    r.Help_Set(("Edit group removed from %d tracks"):format(n), false)
    return
  end
end
-- find the first group nobody uses for media edits
local used = 0
for i = 0, r.CountTracks(0) - 1 do local t = r.GetTrack(0, i); used = used | lead(t) | follow(t) end
local free
for b = 0, 31 do if used & (1 << b) == 0 then free = 1 << b break end end
if not free then free = 1 end
for _, t in ipairs(sel) do
  -- leave any other edit group first, then join this one
  r.GetSetTrackGroupMembership(t, "MEDIA_EDIT_LEAD", 0xFFFFFFFF, 0)
  r.GetSetTrackGroupMembership(t, "MEDIA_EDIT_FOLLOW", 0xFFFFFFFF, 0)
  r.GetSetTrackGroupMembership(t, "MEDIA_EDIT_LEAD", free, free)
  r.GetSetTrackGroupMembership(t, "MEDIA_EDIT_FOLLOW", free, free)
end
-- make sure the clutch is engaged (groups enabled), otherwise nothing would move together
local id
for c = 40000, 43000 do local nm = r.kbd_getTextFromCmd(c, 0) if nm == "Track: Toggle all track grouping enabled" then id = c break end end
local note = ""
if id and r.GetToggleCommandState(id) == 0 then r.Main_OnCommand(id, 0); note = "  (grouping was OFF - switched it on)" end
r.Undo_EndBlock2(0, "Edit group from selected tracks", -1)
local gnum = 0; for b = 0, 31 do if free == (1 << b) then gnum = b + 1 end end
r.Help_Set(("Edit group %d: %d tracks edit together. Clutch = Cmd+Shift+G%s"):format(gnum, n, note), false)
