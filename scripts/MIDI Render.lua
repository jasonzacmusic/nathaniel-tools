-- @description MIDI Render
-- @version 1.0.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about Export project MIDI with a proper time-selection guard.
-- @changelog
--   1.0.0 - first public release. Crash-hardened (GUID identity + ValidatePtr2),
--           signature-based change detection, shared safety library.

-- MIDI Render (safe)
-- Replaces "Custom: Midi Render".  Shift+Control+M used to be wired straight to raw
-- 40849, bypassing the time-selection guard entirely.
-- Here: only build a time selection if there isn't one, prefer selected items,
-- fall back to the whole project, then export.
local r = reaper

local s, e = r.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)

if s == e then
  if r.CountSelectedMediaItems(0) > 0 then
    r.Main_OnCommand(40290, 0)                 -- time selection to items
  else
    -- whole project extent
    local first, last = math.huge, 0
    for i = 0, r.CountMediaItems(0) - 1 do
      local it = r.GetMediaItem(0, i)
      local p = r.GetMediaItemInfo_Value(it, "D_POSITION")
      local l = r.GetMediaItemInfo_Value(it, "D_LENGTH")
      if p < first then first = p end
      if p + l > last then last = p + l end
    end
    if last == 0 then
      r.MB("Nothing to export - no items in this project.", "MIDI Render", 0)
      return
    end
    r.GetSet_LoopTimeRange2(0, true, false, first, last, false)
  end
end

r.Main_OnCommand(40849, 0)                     -- File: Export project MIDI...
