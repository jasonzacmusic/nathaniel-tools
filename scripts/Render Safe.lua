-- @description Render Safe (flush the plugins, then open the Render dialog)
-- @version 1.2.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about
--   Renders used to start with a burst of stray audio: reverb/delay tails and
--   plugin buffers left over from wherever playback last was. Measured on the
--   studio Mac: after playing a section and rendering the top of the song, the
--   first half-second of the file carried a -32 dBFS tail that was not in the
--   song - even with REAPER's "delay render start" on. Jason's hand workaround was
--   "play 5 s of silence at the end of the project, then render". This script does
--   exactly that, automatically:
--     1. stops, jumps past the end of the project, plays 4 s of silence through
--        every plugin so every tail decays, stops, puts the cursor back
--     2. opens File > Render. Press Render as usual.
--   A countdown appears at the mouse the moment the key is pressed, so the
--   4 s of silence never looks like "nothing happened".
--   Bound to your render keys (F14, Cmd+Opt+R).
-- @changelog
--   1.2.0 - shows a countdown at the mouse straight away (the silent 4 s looked like the key did nothing);
--           refuses to run while recording; pressing it twice cancels cleanly and puts the cursor back;
--           writes one line per press to render-safe.log in the REAPER folder.
--   1.1.0 - flushes by playing silence past the end (the thing that really clears the tails);
--           no longer forces "delay render start" (that pops a 30 s dialog on one-click renders).
--   1.0.0 - first version.

local r = reaper
local SILENCE = 4.0   -- seconds of silence played through the plugins

-- pressing the key again while it counts down cancels it instead of asking "terminate script?"
if r.set_action_options then r.set_action_options(1) end

local function log(msg)
  local f = io.open(r.GetResourcePath() .. "/render-safe.log", "a")
  if f then f:write(os.date("%Y-%m-%d %H:%M:%S  ") .. msg .. "\n"); f:close() end
end

local function tip(text)
  local x, y = r.GetMousePosition()
  r.TrackCtl_SetToolTip(text, x + 18, y + 18, true)
end

if r.GetPlayState() & 4 == 4 then
  tip("Render Safe: not while recording")
  log("refused: recording")
  return
end

log("pressed")
local cursor = r.GetCursorPosition()
local done = false
if r.GetPlayState() & 1 == 1 then r.Main_OnCommand(1016, 0) end   -- Transport: Stop
r.PreventUIRefresh(1)
r.SetEditCurPos2(0, r.GetProjectLength(0) + 5, false, false)
r.PreventUIRefresh(-1)
r.Main_OnCommand(1007, 0)                                          -- Transport: Play (silence: nothing lives out there)

r.atexit(function()
  r.TrackCtl_SetToolTip("", 0, 0, true)
  if not done then                                                 -- cancelled by a second press
    r.Main_OnCommand(1016, 0)
    r.SetEditCurPos2(0, cursor, true, false)
    log("cancelled")
  end
end)

local t0 = r.time_precise()
local shown = -1
local function tick()
  local left = math.ceil(SILENCE - (r.time_precise() - t0))
  if left > 0 then
    if left ~= shown then                                          -- redraw once a second, not every frame
      shown = left
      tip("Render Safe: clearing plugin tails...  Render window in " .. left)
    end
    return r.defer(tick)
  end
  done = true
  r.Main_OnCommand(1016, 0)                                        -- Stop (Flush FX on stop is on as well)
  r.SetEditCurPos2(0, cursor, true, false)
  r.TrackCtl_SetToolTip("", 0, 0, true)
  log("render window opened")
  r.Main_OnCommand(40015, 0)                                       -- File: Render project to disk...
end
tick()
