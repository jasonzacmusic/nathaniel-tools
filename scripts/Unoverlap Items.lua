-- @description Unoverlap Items (selected items, or all items on selected tracks)
-- @version 1.1.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about
--   Wherever two items on the same track overlap, the EARLIER item is cut at the
--   start of the later one, so items butt instead of sitting on top of each
--   other - and the tangled crossfade at that join (a long fade-out on the
--   earlier item / long fade-in on the later one) is reset to REAPER's short
--   default fade. Fades elsewhere (a song-ending fade-out, say) are left alone.
--   Works on the selected items; with none, on the selected tracks; with no
--   selection at all, on every track. One undo step.
-- @changelog
--   1.1.0 - also resets the crossfade at every join it fixes; no selection = whole project.
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
if #tracks == 0 then for i = 0, r.CountTracks(0) - 1 do tracks[#tracks + 1] = r.GetTrack(0, i) end end
local DEF = (r.SNM_GetDoubleConfigVar and r.SNM_GetDoubleConfigVar("deffadelen", 0.02)) or 0.02
if not DEF or DEF <= 0 or DEF > 1 then DEF = 0.02 end
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
    if ap + al > bp + 1e-9 and bp > ap then
      r.SetMediaItemInfo_Value(a, "D_LENGTH", bp - ap)
      -- the join is clean now: give it the normal short fades, not the old crossfade
      r.SetMediaItemInfo_Value(a, "D_FADEOUTLEN", DEF); r.SetMediaItemInfo_Value(a, "D_FADEOUTLEN_AUTO", -1)
      r.SetMediaItemInfo_Value(b, "D_FADEINLEN", DEF);  r.SetMediaItemInfo_Value(b, "D_FADEINLEN_AUTO", -1)
      fixed = fixed + 1
    end
  end
end
r.PreventUIRefresh(-1); r.UpdateArrange()
r.Undo_EndBlock2(0, "Unoverlap items", -1)
r.Help_Set(("Unoverlap: %d overlap(s) fixed, joins given the normal short fade"):format(fixed), false)
