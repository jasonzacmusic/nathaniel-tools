-- @description New Project Defaults (snap on, relative snap on, repeat off)
-- @version 1.0.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about
--   Runs quietly in the background (start it from __startup.lua or the Actions
--   list). Every time a NEW, never-saved project appears - REAPER launch, File >
--   New project, a new project tab - it switches snapping ON, relative grid
--   snap ON, and transport repeat (loop) OFF. Projects you open from disk are
--   left exactly as they were saved.
-- @changelog
--   1.0.0 - first version.

local r = reaper
local seen = {}   -- project pointer -> true once we have applied

local function apply(proj)
  if r.GetToggleCommandState(1157) ~= 1 then r.Main_OnCommand(1157, 0) end     -- Options: Toggle snapping -> on
  if r.SNM_GetIntConfigVar and r.SNM_GetIntConfigVar("relsnap", 0) ~= 1 then r.Main_OnCommand(41052, 0) end -- relative snap on
  if r.GetSetRepeat(-1) == 1 then r.GetSetRepeat(0) end                         -- repeat off
end

local function tick()
  local i = 0
  while true do
    local proj, path = r.EnumProjects(i)
    if not proj then break end
    if not seen[proj] and (path == nil or path == "") and r.CountTracks(proj) == 0 then
      seen[proj] = true
      local cur = r.EnumProjects(-1)
      if cur == proj then apply(proj) end
    end
    i = i + 1
  end
  r.defer(function() r.defer(tick) end)   -- ~ every other UI frame is plenty
end
tick()
