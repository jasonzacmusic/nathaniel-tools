-- @description Render Safe (open the Render dialog with the artifact guards on)
-- @version 1.0.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about
--   Renders used to start with a burst of stray audio - plugin tails and buffers
--   from wherever playback last was, and plugins (Waves, samplers) that are not
--   ready on the first block. Jason's workaround was "play silence for 5 s, then
--   render". This does the equivalent automatically and opens the Render dialog:
--     * stops playback and flushes every FX buffer
--     * turns on REAPER's "Delay render start to allow FX to initialize" with a
--       2-second delay, for this project (survives save; presets keep it too)
--     * then opens File > Render. Press your render key as before.
-- @changelog
--   1.0.0 - first version.

local r = reaper
local DELAY_FLAG = 16 << 16      -- RENDER_SETTINGS: delay render start
r.Undo_BeginBlock2(0)
-- 1) stop + flush FX (Preferences > Playback "Flush FX on stop" is on; a stop triggers it)
if r.GetPlayState() ~= 0 then r.Main_OnCommand(1016, 0) end            -- Transport: Stop
-- belt and braces: toggle FX bypass on/off per track would reset some plugins but
-- also moves parameters; instead run the offline/online flip REAPER uses for a
-- clean state only when the project is small? No - keep it simple and safe:
-- 2) project render settings: delay render start 2 s
local s = r.GetSetProjectInfo(0, "RENDER_SETTINGS", 0, false)
if s & DELAY_FLAG == 0 then r.GetSetProjectInfo(0, "RENDER_SETTINGS", s | DELAY_FLAG, true) end
local d = r.GetSetProjectInfo(0, "RENDER_DELAY", 0, false)
if not d or d < 2 then r.GetSetProjectInfo(0, "RENDER_DELAY", 2, true) end
r.Undo_EndBlock2(0, "Render Safe: delay render start", -1)
-- 3) open the Render dialog
r.Main_OnCommand(40015, 0)      -- File: Render project to disk...
