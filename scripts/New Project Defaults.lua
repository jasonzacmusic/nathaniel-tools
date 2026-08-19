-- @description New Project Defaults (snap on, relative snap on, repeat off)
-- @version 1.2.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about
--   Runs quietly in the background (start it from __startup.lua or the Actions
--   list). Every project that comes to the front for the first time - REAPER
--   launch, File > New, a new tab, or one opened from disk - gets transport
--   repeat (loop) switched OFF and the mixer shown. New, never-saved projects also get snapping ON
--   and relative grid snap ON. (Saved projects keep their own snap settings.)
-- @changelog
--   1.2.0 - the mixer is shown whenever a project comes to the front.
--   1.1.0 - repeat is switched off for EVERY project that comes to the front, not only new ones.
--   1.0.0 - first version.

local r = reaper
local seen = {}   -- project pointer -> true once we have applied

local function applyNew()
  if r.GetToggleCommandState(1157) ~= 1 then r.Main_OnCommand(1157, 0) end     -- Options: Toggle snapping -> on
  if r.SNM_GetIntConfigVar and r.SNM_GetIntConfigVar("relsnap", 0) ~= 1 then r.Main_OnCommand(41052, 0) end -- relative snap on
end
local function repeatOff()
  if r.GetSetRepeat(-1) == 1 then r.GetSetRepeat(0) end                         -- repeat (loop) off
end
local function mixerOn()
  if r.GetToggleCommandState(40078) ~= 1 then r.Main_OnCommand(40078, 0) end    -- View: Toggle mixer visible -> on
end

local function tick()
  local cur = r.EnumProjects(-1)
  if cur and not seen[cur] then
    seen[cur] = true
    local _, path = r.EnumProjects(-1)
    repeatOff()
    mixerOn()
    if (path == nil or path == "") and r.CountTracks(cur) == 0 then applyNew() end
  end
  r.defer(function() r.defer(tick) end)
end
tick()
