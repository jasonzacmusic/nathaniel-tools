-- @description Render Safe (flush the plugins, then open the Render dialog)
-- @version 1.3.0
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
--     2. loads the "Jason Zac Default" render preset (format, sample rate,
--        regions, file name) into the project, then opens File > Render.
--        Press Render as usual.
--   A countdown appears at the mouse the moment the key is pressed, so the
--   4 s of silence never looks like "nothing happened".
--   Bound to your render keys (F14, Cmd+Opt+R).
-- @changelog
--   1.3.0 - loads the "Jason Zac Default" render preset every time, so Render always starts from it.
--   1.2.0 - shows a countdown at the mouse straight away (the silent 4 s looked like the key did nothing);
--           refuses to run while recording; pressing it twice cancels cleanly and puts the cursor back;
--           writes one line per press to render-safe.log in the REAPER folder.
--   1.1.0 - flushes by playing silence past the end (the thing that really clears the tails);
--           no longer forces "delay render start" (that pops a 30 s dialog on one-click renders).
--   1.0.0 - first version.

local r = reaper
local SILENCE = 4.0   -- seconds of silence played through the plugins
local PRESET = "Jason Zac Default"   -- render preset loaded before the Render window opens

-- pressing the key again while it counts down cancels it instead of asking "terminate script?"
if r.set_action_options then r.set_action_options(1) end

local function log(msg)
  local f = io.open(r.GetResourcePath() .. "/render-safe.log", "a")
  if f then f:write(os.date("%Y-%m-%d %H:%M:%S  ") .. msg .. "\n"); f:close() end
end

-- Read one preset from reaper-render.ini and put it into the project's render settings.
-- Returns true when the preset was found.
local function loadPreset(name)
  local f = io.open(r.GetResourcePath() .. "/reaper-render.ini", "r")
  if not f then return false end
  local text = f:read("a"); f:close()
  local function q(s) return s:find(" ") and ('"' .. s .. '"') or s end
  local key = q(name):gsub("%p", "%%%0")
  local srate, chans, fmt = text:match("<RENDERPRESET " .. key .. " (%d+) (%d+)[^\n]*\n%s*(%S+)")
  local out = text:match("RENDERPRESET_OUTPUT " .. key .. " ([^\n]+)")
  if not (srate and out) then return false end
  local fields = {}
  local pos = 1
  while pos <= #out do                                     -- split, keeping "quoted strings" whole
    local a, b, quoted = out:find('^"([^"]*)"%s*', pos)
    if a then fields[#fields + 1] = quoted; pos = b + 1
    else
      local c, d, word = out:find("^(%S+)%s*", pos)
      if not c then break end
      fields[#fields + 1] = word; pos = d + 1
    end
  end
  -- RENDERPRESET_OUTPUT name: bounds start end settings ? pattern ? directory ...
  r.GetSetProjectInfo(0, "RENDER_SRATE", tonumber(srate), true)
  r.GetSetProjectInfo(0, "RENDER_CHANNELS", tonumber(chans), true)
  r.GetSetProjectInfo_String(0, "RENDER_FORMAT", fmt, true)
  r.GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", tonumber(fields[1]) or 1, true)
  if tonumber(fields[1]) == 0 then
    r.GetSetProjectInfo(0, "RENDER_STARTPOS", tonumber(fields[2]) or 0, true)
    r.GetSetProjectInfo(0, "RENDER_ENDPOS", tonumber(fields[3]) or 0, true)
  end
  r.GetSetProjectInfo(0, "RENDER_SETTINGS", tonumber(fields[4]) or 0, true)
  if fields[6] then r.GetSetProjectInfo_String(0, "RENDER_PATTERN", fields[6], true) end
  if fields[8] and fields[8] ~= "" then r.GetSetProjectInfo_String(0, "RENDER_FILE", fields[8], true) end
  return true
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
  log(loadPreset(PRESET) and ("preset loaded: " .. PRESET) or ("preset NOT found: " .. PRESET))
  log("render window opened")
  r.Main_OnCommand(40015, 0)                                       -- File: Render project to disk...
end
tick()
