-- @description Render Safe (flush the plugins, then open the Render dialog)
-- @version 1.1.0
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
--   Bound to your render keys (F14, Cmd+Opt+R).
-- @changelog
--   1.1.0 - flushes by playing silence past the end (the thing that really clears the tails);
--           no longer forces "delay render start" (that pops a 30 s dialog on one-click renders).
--   1.0.0 - first version.

local r = reaper
local SILENCE = 4.0   -- seconds of silence played through the plugins

local cursor = r.GetCursorPosition()
local wasPlaying = r.GetPlayState() & 1 == 1
if wasPlaying then r.Main_OnCommand(1016, 0) end           -- Transport: Stop
local endPos = r.GetProjectLength(0) + 5
r.PreventUIRefresh(1)
r.SetEditCurPos2(0, endPos, false, false)
r.PreventUIRefresh(-1)
r.Main_OnCommand(1007, 0)                                  -- Transport: Play (silence: nothing lives out there)
local t0 = r.time_precise()
local function tick()
  if r.time_precise() - t0 < SILENCE then r.defer(tick) return end
  r.Main_OnCommand(1016, 0)                                -- Stop (Flush FX on stop is on as well)
  r.SetEditCurPos2(0, cursor, true, false)
  r.Main_OnCommand(40015, 0)                               -- File: Render project to disk...
end
r.defer(tick)
