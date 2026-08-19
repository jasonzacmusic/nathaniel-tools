-- @description Trim Left No Overlap (to edit cursor)
-- @version 1.0.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about
--   Trim the LEFT edge of the selected items to the edit cursor - and if that
--   would push the item over its neighbour on the same track, trim the
--   neighbour's right edge to the cursor too. Items butt, they never overlap,
--   so no surprise crossfades. Replaces "Item edit: Trim left edge of item to
--   edit cursor" (Jason's Z key).
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
  local len = r.GetMediaItemInfo_Value(it, "D_LENGTH")
  local fin = pos + len
  if cur < fin then
    -- move the left edge to the cursor, keeping the audio where it is
    local delta = cur - pos
    for tk = 0, r.CountTakes(it) - 1 do
      local take = r.GetTake(it, tk)
      local rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
      local off = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
      r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", off + delta * rate)
    end
    r.SetMediaItemInfo_Value(it, "D_POSITION", cur)
    r.SetMediaItemInfo_Value(it, "D_LENGTH", fin - cur)
    -- any item to the LEFT on the same track that now reaches past the cursor: cut it at the cursor
    local tr = r.GetMediaItem_Track(it)
    for j = 0, r.CountTrackMediaItems(tr) - 1 do
      local o = r.GetTrackMediaItem(tr, j)
      if o ~= it then
        local op = r.GetMediaItemInfo_Value(o, "D_POSITION")
        local ol = r.GetMediaItemInfo_Value(o, "D_LENGTH")
        if op < cur and op + ol > cur then r.SetMediaItemInfo_Value(o, "D_LENGTH", cur - op) end
      end
    end
  end
end
r.PreventUIRefresh(-1); r.UpdateArrange()
r.Undo_EndBlock2(0, "Trim left edge to cursor (no overlap)", -1)
