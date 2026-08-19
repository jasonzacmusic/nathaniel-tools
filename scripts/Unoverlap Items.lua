-- @description Unoverlap Items (selected items, or all items on selected tracks)
-- @version 1.0.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about
--   Wherever two items on the same track overlap, the EARLIER item is cut at the
--   start of the later one, so items butt instead of sitting on top of each
--   other with a tangled crossfade. Works on the selected items; with no item
--   selected, on every item of the selected tracks. Fades are left as they are.
-- @changelog
--   1.0.0 - first version.

local r = reaper
local tracks, seen = {}, {}
if r.CountSelectedMediaItems(0) > 0 then
  for i = 0, r.CountSelectedMediaItems(0) - 1 do
    local tr = r.GetMediaItem_Track(r.GetSelectedMediaItem(0, i))
    if not seen[tr] then seen[tr] = true; tracks[#tracks + 1] = tr end
  end
else
  for i = 0, r.CountSelectedTracks(0) - 1 do tracks[#tracks + 1] = r.GetSelectedTrack(0, i) end
end
if #tracks == 0 then r.ShowMessageBox("Select some items, or some tracks, first.", "Unoverlap Items", 0) return end
r.Undo_BeginBlock2(0); r.PreventUIRefresh(1)
local fixed = 0
for _, tr in ipairs(tracks) do
  local items = {}
  for j = 0, r.CountTrackMediaItems(tr) - 1 do items[#items + 1] = r.GetTrackMediaItem(tr, j) end
  table.sort(items, function(a, b) return r.GetMediaItemInfo_Value(a, "D_POSITION") < r.GetMediaItemInfo_Value(b, "D_POSITION") end)
  for k = 1, #items - 1 do
    local a, b = items[k], items[k + 1]
    local ap = r.GetMediaItemInfo_Value(a, "D_POSITION"); local al = r.GetMediaItemInfo_Value(a, "D_LENGTH")
    local bp = r.GetMediaItemInfo_Value(b, "D_POSITION")
    if ap + al > bp + 1e-9 and bp > ap then r.SetMediaItemInfo_Value(a, "D_LENGTH", bp - ap); fixed = fixed + 1 end
  end
end
r.PreventUIRefresh(-1); r.UpdateArrange()
r.Undo_EndBlock2(0, "Unoverlap items", -1)
r.Help_Set(("Unoverlap: %d overlap(s) fixed"):format(fixed), false)
