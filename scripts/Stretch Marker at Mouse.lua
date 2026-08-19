-- @description Stretch Marker at Mouse
-- @version 1.0.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about
--   Adds a stretch marker exactly under the mouse pointer, in the item you are
--   pointing at, without moving the edit cursor. Meant to be assigned as a mouse
--   modifier: Preferences > Mouse modifiers > "Media item bottom half" > left
--   click > Action list > this script. (Nathaniel Tools sets Control+click.)
--   Needs SWS (for the mouse-position lookup).
-- @changelog
--   1.0.0 - first version.

local r = reaper
if not r.BR_GetMouseCursorContext then
  r.ShowMessageBox("Stretch Marker at Mouse needs the SWS extension (sws-extension.org).", "Stretch Marker at Mouse", 0) return
end
local window, segment, details = r.BR_GetMouseCursorContext()
local item = r.BR_GetMouseCursorContext_Item()
local pos  = r.BR_GetMouseCursorContext_Position()
if not item or not pos or pos < 0 then return end
local take = r.GetActiveTake(item)
if not take or r.TakeIsMIDI(take) then return end
local ipos = r.GetMediaItemInfo_Value(item, "D_POSITION")
local ilen = r.GetMediaItemInfo_Value(item, "D_LENGTH")
if pos < ipos or pos > ipos + ilen then return end
-- snap like REAPER would if snap is on
local snapped = r.SnapToGrid(0, pos)
if r.GetToggleCommandState(1157) == 1 then pos = snapped end
r.Undo_BeginBlock2(0)
local idx = r.SetTakeStretchMarker(take, -1, pos - ipos)
r.Undo_EndBlock2(0, "Add stretch marker at mouse", -1)
r.UpdateItemInProject(item)
