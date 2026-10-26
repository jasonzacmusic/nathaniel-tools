-- @description MIDI Inline Toggle (see and fix the notes inside the item, no separate MIDI editor)
-- @version 1.1.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about
--   Press once: the selected MIDI items (or the one under the mouse when nothing
--   is selected) open their notes right inside the item in the arrange view, and
--   the track grows tall enough to read and drag single notes. Press again: the
--   notes fold away and the track goes back to the height it had.
--   Made for quick fixes - a wrong note, a late note - without opening the big
--   MIDI editor window.
--   Also set as the double-click on items: double-clicking a MIDI item opens its
--   notes in place; double-clicking an audio item does what it always did.
-- @changelog
--   1.1.0 - works from a double-click: acts on the item under the mouse first; audio items keep their old double-click.
--   1.0.0 - first version.

local r = reaper
local OPEN, CLOSE = 40847, 41887   -- Item: Open / Close item inline editors
local TALL = 260                    -- track height (px) while the notes are open
local KEY = "nt_inline_h"           -- remembers each track's height before we grew it

local function midiTakes()
  local list = {}
  for i = 0, r.CountSelectedMediaItems(0) - 1 do
    local item = r.GetSelectedMediaItem(0, i)
    local take = r.GetActiveTake(item)
    if take and r.TakeIsMIDI(take) then list[#list + 1] = { item = item, take = take } end
  end
  return list
end

local DEFAULT_DBLCLK = 40153        -- what a double-click on an item did before (open in editor)

local under = r.BR_ItemAtMouseCursor and r.BR_ItemAtMouseCursor()
if under then                                               -- the item under the mouse wins
  local take = r.GetActiveTake(under)
  if not (take and r.TakeIsMIDI(take)) then                 -- audio etc.: keep the old behaviour
    r.Main_OnCommand(DEFAULT_DBLCLK, 0)
    return
  end
  if not r.IsMediaItemSelected(under) then
    r.SelectAllMediaItems(0, false)
    r.SetMediaItemSelected(under, true)
  end
end
local takes = midiTakes()
if #takes == 0 then
  local x, y = r.GetMousePosition()
  r.TrackCtl_SetToolTip("Select a MIDI item (or point at one) first", x + 18, y + 18, true)
  return
end

local anyOpen = false
if r.BR_IsMidiOpenInInlineEditor then
  for _, t in ipairs(takes) do
    if r.BR_IsMidiOpenInInlineEditor(t.take) then anyOpen = true; break end
  end
end

r.Undo_BeginBlock()
r.PreventUIRefresh(1)
local seen = {}
for _, t in ipairs(takes) do
  local track = r.GetMediaItem_Track(t.item)
  if not seen[track] then
    seen[track] = true
    local ok, saved = r.GetSetMediaTrackInfo_String(track, "P_EXT:" .. KEY, "", false)
    if anyOpen then
      if ok and saved ~= "" then                             -- back to the height it had before
        r.SetMediaTrackInfo_Value(track, "I_HEIGHTOVERRIDE", tonumber(saved) or 0)
        r.GetSetMediaTrackInfo_String(track, "P_EXT:" .. KEY, "", true)
      end
    else
      local h = r.GetMediaTrackInfo_Value(track, "I_TCPH")
      if h < TALL then
        r.GetSetMediaTrackInfo_String(track, "P_EXT:" .. KEY,
          tostring(math.floor(r.GetMediaTrackInfo_Value(track, "I_HEIGHTOVERRIDE"))), true)
        r.SetMediaTrackInfo_Value(track, "I_HEIGHTOVERRIDE", TALL)
      end
    end
  end
end
r.Main_OnCommand(anyOpen and CLOSE or OPEN, 0)
r.PreventUIRefresh(-1)
r.TrackList_AdjustWindows(false)
r.UpdateArrange()
r.Undo_EndBlock(anyOpen and "Close MIDI notes in item" or "Show MIDI notes in item", -1)
