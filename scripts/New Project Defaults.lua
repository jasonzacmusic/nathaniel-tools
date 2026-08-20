-- @description New Project Defaults (snap on, relative snap on, repeat off, mixer in front)
-- @version 1.5.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about
--   Runs quietly in the background (start it from __startup.lua or the Actions
--   list). Every project that comes to the front for the first time - REAPER
--   launch, File > New, a new tab, or one opened from disk - gets transport
--   repeat (loop) switched OFF, the mixer shown AND pulled to the front of its
--   docker, and "trim content behind items" ON with auto-crossfade OFF
--   (projects save their own copy of that). New, never-saved projects also get
--   snapping ON and relative grid snap ON. (Saved projects keep their own snap
--   settings.)
-- @changelog
--   1.5.0 - the mixer is pulled to the FRONT of its docker tab row. Showing it was not enough: the
--           studio apps open into the same docker at launch and one of them ended up in front.
--   1.4.1 - render guard moved to the "Render Safe" script (setting it here marked every project modified).
--   1.3.0 - trim-behind ON / auto-crossfade OFF re-asserted for every project (projects save their own copy).
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
local function trimBehindOn()
  -- "Trim content behind media items" is saved INSIDE each project (AUTOXFADE line),
  -- so an older project switches it back off when it loads. Re-assert it.
  if r.GetToggleCommandState(41117) ~= 1 then r.Main_OnCommand(41120, 0) end
  if r.GetToggleCommandState(40041) == 1 then r.Main_OnCommand(40041, 0) end   -- auto-crossfade off
end

-- Show the mixer AND make it the front tab. The studio apps share the same
-- docker; whichever opened last was winning the tab row, so "mixer visible"
-- read as ON while a tool page was actually on screen.
local function mixerToFront()
  if r.GetToggleCommandState(40078) ~= 1 then r.Main_OnCommand(40078, 0) end    -- View: Toggle mixer visible -> on
  if r.BR_Win32_GetMixerHwnd and r.DockWindowActivate then
    local hwnd = r.BR_Win32_GetMixerHwnd(false)
    if hwnd then r.DockWindowActivate(hwnd) end
  end
end

local function tick()
  local cur = r.EnumProjects(-1)
  if cur and not seen[cur] then
    seen[cur] = true
    local _, path = r.EnumProjects(-1)
    repeatOff()
    trimBehindOn()
    if (path == nil or path == "") and r.CountTracks(cur) == 0 then applyNew() end
    -- last, and after the tool windows have had a chance to open, so the mixer
    -- is the tab left in front
    local delay = 60
    local function settle()
      delay = delay - 1
      if delay > 0 then r.defer(settle) else mixerToFront() end
    end
    r.defer(settle)
  end
  r.defer(function() r.defer(tick) end)
end
tick()
