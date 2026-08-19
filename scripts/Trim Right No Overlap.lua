-- @description Trim Right No Overlap (to edit cursor)
-- @version 1.0.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about
--   Trim the RIGHT edge of the selected items to the edit cursor - and if that
--   would push the item over its neighbour on the same track, move the
--   neighbour's left edge to the cursor too (its audio stays in place). Items
--   butt, they never overlap. Replaces "Item edit: Trim right edge of item to
--   edit cursor" (Jason's X key).
-- @changelog
--   1.0.0 - first version.

local r = reaper
local cur = r.GetCursorPosition()
local n = r.CountSelectedMediaItems(0)
if n == 0 then return end
r.Undo_BeginBlock2(0); r.PreventUIRefresh(1)
local sel = {}
for i = 0, n - 1 do sel[#sel + 1] = r.GetSelectedMediaItem(0, i) end
for _, it in ipairs(sel) do
  local pos = r.GetMediaItemInfo_Value(it, "D_POSITION")
  if cur > pos then
    r.SetMediaItemInfo_Value(it, "D_LENGTH", cur - pos)
    local tr = r.GetMediaItem_Track(it)
    for j = 0, r.CountTrackMediaItems(tr) - 1 do
      local o = r.GetTrackMediaItem(tr, j)
      if o ~= it then
        local op = r.GetMediaItemInfo_Value(o, "D_POSITION")
        local ol = r.GetMediaItemInfo_Value(o, "D_LENGTH")
        if op < cur and op + ol > cur and op > pos then
          local delta = cur - op
          for tk = 0, r.CountTakes(o) - 1 do
            local take = r.GetTake(o, tk)
            local rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
            local off = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
            r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", off + delta * rate)
          end
          r.SetMediaItemInfo_Value(o, "D_POSITION", cur)
          r.SetMediaItemInfo_Value(o, "D_LENGTH", ol - delta)
        end
      end
    end
  end
end
r.PreventUIRefresh(-1); r.UpdateArrange()
r.Undo_EndBlock2(0, "Trim right edge to cursor (no overlap)", -1)
