-- @description My Project Settings (every project opens with Jason's own project settings)
-- @version 1.1.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about
--   Runs quietly in the background (started from __startup.lua). The first time a project comes
--   to the front, its project settings are compared with Jason's saved set (data/My Project
--   Settings.txt): sample rate, recording format and folder, item mixing, crossfades and trim,
--   grid, timebase, pitch mode, pan law, ripple, locking, take lanes, metronome and the rest of
--   File > Project settings. Tracks, FX, tempo, markers, zoom and render settings are never touched.
--   - A saved project that differs is backed up to its Backups folder, rewritten with the settings
--     and reloaded in the same tab (once; after that it matches).
--   - A project with unsaved changes, or a new unsaved one, gets the settings applied live instead.
--   Nothing happens while REAPER is playing or recording; it waits.
--   To change the set: open a project that is set up the way you like, save it, and run
--   "Save My Project Settings".
-- @changelog
--   1.1.0 - Freestyle Riffs and Tutorials sessions are left alone (they carry their own setup: metronome,
--           pre-roll and snapping off).
--   1.0.0 - first version.

local r = reaper
local base = r.GetResourcePath() .. "/Scripts/Nathaniel Tools/"
local DEFAULTS = base .. "data/My Project Settings.txt"
local LOG = base .. "data/My Project Settings.log"

-- The project-level settings we own. Anything else in the file is left as it is.
local SINGLES = { "AUTHOR", "RIPPLE", "GROUPOVERRIDE", "AUTOXFADE", "ENVATTACH", "POOLEDENVATTACH",
  "TCPUIFLAGS", "MIXERUIFLAGS", "PEAKGAIN", "FEEDBACK", "PANLAW", "PANLAWFLAGS", "PANMODE", "GRID",
  "TIMEMODE", "VIDEO_CONFIG", "USE_REC_CFG", "RECMODE", "SMPTESYNC", "LOOPGRAN", "RECORD_PATH",
  "TIMELOCKMODE", "TEMPOENVLOCKMODE", "ITEMMIX", "DEFPITCHMODE", "MISCOPTS", "TAKELANE", "SAMPLERATE",
  "LOCK", "GLOBAL_AUTO", "MASTER_PANMODE", "MASTERTRACKVIEW", "RULERHEIGHT" }
local BLOCKS = { "RECORD_CFG", "APPLYFX_CFG", "METRONOME" }

local function log(s)
  local f = io.open(LOG, "a")
  if f then f:write(os.date("%Y-%m-%d %H:%M:%S  ") .. s .. "\n"); f:close() end
end

local function readLines(path)
  local f = io.open(path, "rb"); if not f then return nil end
  local t = {}
  for line in f:lines() do t[#t + 1] = (line:gsub("\r$", "")) end
  f:close()
  return t
end

-- Top-level (depth 1) single lines and blocks before the first track.
-- singles[key] = line index; blocks[key] = {first, last}; tempoAt = index of the TEMPO line.
local function header(lines)
  local singles, blocks, depth, open, tempoAt = {}, {}, 0, nil, nil
  for i, line in ipairs(lines) do
    local s = line:match("^%s*(.-)%s*$")
    if depth == 1 and s:match("^<TRACK") then break end
    if s:sub(1, 1) == "<" then
      if depth == 1 then
        local k = s:match("^<([%w_]+)")
        if k and not blocks[k] then open = k; blocks[k] = { i, i } end
      end
      depth = depth + 1
    elseif s == ">" then
      depth = depth - 1
      if depth == 1 and open then blocks[open][2] = i; open = nil end
    elseif depth == 1 then
      local k = s:match("^([%u%d_]+)")
      if k and not singles[k] then singles[k] = i end
      if k == "TEMPO" and not tempoAt then tempoAt = i end
    end
  end
  return singles, blocks, tempoAt
end

local DEF -- { singles = {key = "LINE"}, blocks = {key = {"lines", ...}} }
local function loadDefaults()
  local lines = readLines(DEFAULTS)
  if not lines then return nil end
  local sg, bl = header(lines)
  local d = { singles = {}, blocks = {} }
  for _, k in ipairs(SINGLES) do if sg[k] then d.singles[k] = lines[sg[k]]:match("^%s*(.-)%s*$") end end
  for _, k in ipairs(BLOCKS) do
    if bl[k] then
      local t = {}
      for i = bl[k][1], bl[k][2] do t[#t + 1] = lines[i]:match("^%s*(.-)%s*$") end
      d.blocks[k] = t
    end
  end
  return d
end

local function trim(s) return (s:match("^%s*(.-)%s*$")) end

-- Returns the patched lines and a list of what changed (empty list = already matches).
local function patch(lines)
  local sg, bl, tempoAt = header(lines)
  if not tempoAt then return nil, {} end
  local indent = lines[tempoAt]:match("^(%s*)")
  local replace, drop, insert, changed = {}, {}, {}, {}
  for _, k in ipairs(SINGLES) do
    local want = DEF.singles[k]
    if want then
      if sg[k] then
        if trim(lines[sg[k]]) ~= want then replace[sg[k]] = { indent .. want }; changed[#changed + 1] = k end
      else insert[#insert + 1] = indent .. want; changed[#changed + 1] = "+" .. k end
    elseif sg[k] then drop[sg[k]] = true; changed[#changed + 1] = "-" .. k end
  end
  for _, k in ipairs(BLOCKS) do
    local want = DEF.blocks[k]
    if want then
      local function render(into)
        for j, l in ipairs(want) do into[#into + 1] = (j == 1 or j == #want) and indent .. l or indent .. "  " .. l end
      end
      if bl[k] then
        local same = (bl[k][2] - bl[k][1] + 1) == #want
        if same then for j = 1, #want do if trim(lines[bl[k][1] + j - 1]) ~= want[j] then same = false; break end end end
        if not same then
          local t = {}; render(t); replace[bl[k][1]] = t
          for i = bl[k][1] + 1, bl[k][2] do drop[i] = true end
          changed[#changed + 1] = k
        end
      else render(insert); changed[#changed + 1] = "+" .. k end
    end
  end
  if #changed == 0 then return nil, changed end
  local out = {}
  for i, l in ipairs(lines) do
    if i == tempoAt then for _, x in ipairs(insert) do out[#out + 1] = x end end
    if replace[i] then for _, x in ipairs(replace[i]) do out[#out + 1] = x end
    elseif not drop[i] then out[#out + 1] = l end
  end
  return out, changed
end

-- Settings REAPER lets us set on a project that is already open (unsaved or modified).
local function applyLive(proj)
  if not r.SNM_SetIntConfigVarEx then return end
  local s = DEF.singles
  local function num(line, n) if not line then return nil end local i = 0
    for w in line:gmatch("%S+") do if i == n then return tonumber(w) end i = i + 1 end end
  local sr = num(s.SAMPLERATE, 1)
  if sr then
    r.GetSetProjectInfo(proj, "PROJECT_SRATE", sr, true)
    r.GetSetProjectInfo(proj, "PROJECT_SRATE_USE", num(s.SAMPLERATE, 2) or 0, true)
  end
  local ints = { itemmixflag = num(s.ITEMMIX, 1), autoxfade = num(s.AUTOXFADE, 1), miscopts = num(s.MISCOPTS, 1) or 0,
    panmode = num(s.PANMODE, 1), panlawflags = num(s.PANLAWFLAGS, 1) or 0 }
  for k, v in pairs(ints) do if v and r.SNM_GetIntConfigVarEx(proj, k, -99999) ~= -99999 then r.SNM_SetIntConfigVarEx(proj, k, v) end end
  local gd = num(s.GRID, 2)
  if gd and r.SNM_SetDoubleConfigVarEx then r.SNM_SetDoubleConfigVarEx(proj, "projgriddiv", gd) end
  local rp = s.RECORD_PATH and s.RECORD_PATH:match('^RECORD_PATH "([^"]*)"')
  if rp then r.GetSetProjectInfo_String(proj, "RECORD_PATH", rp, true) end
end

local function fixFile(proj, path)
  local lines = readLines(path); if not lines then return end
  local out, changed = patch(lines)
  if not out then return end
  local dir, name = path:match("^(.*)/([^/]+)$")
  r.RecursiveCreateDirectory(dir .. "/Backups", 0)
  local bak = dir .. "/Backups/" .. name:gsub("%.[Rr][Pp][Pp]$", "") .. " before my settings " .. os.date("%Y-%m-%d %H%M%S") .. ".RPP"
  local src = io.open(path, "rb"); local all = src:read("*a"); src:close()
  local eol = all:find("\r\n", 1, true) and "\r\n" or "\n"   -- keep the file's own line endings
  local b = io.open(bak, "wb"); if not b then log("could not back up " .. path); return end
  b:write(all); b:close()
  local tmp = path .. ".mysettings.tmp"
  local f = io.open(tmp, "wb"); if not f then return end
  f:write(table.concat(out, eol) .. eol); f:close()
  if not os.rename(tmp, path) then os.remove(tmp); log("could not write " .. path); return end
  log("fixed " .. path .. "  (" .. table.concat(changed, " ") .. ")  backup: " .. bak)
  if r.EnumProjects(-1) == proj then r.Main_openProject("noprompt:" .. path) end
end

local seen, wait = {}, {}
local function tick()
  local proj, path = r.EnumProjects(-1)
  if proj and DEF and r.GetPlayState() == 0 then
    local key = tostring(proj) .. "|" .. (path or "")
    if not seen[key] then
      wait[key] = (wait[key] or 0) + 1
      if wait[key] > 20 then -- let a project finish opening first
        seen[key] = true
        local skip = path ~= "" and (path:find("/ProjectTemplates/", 1, true) or not path:match("%.[Rr][Pp][Pp]$")
          or path:match("/Freestyle Riffs[^/]*%.[Rr][Pp][Pp]$") or path:match("/Tutorials[^/]*%.[Rr][Pp][Pp]$"))
        if not skip then
          local ok, err = pcall(function()
            if path ~= "" and r.IsProjectDirty(proj) == 0 then fixFile(proj, path) else applyLive(proj) end
          end)
          if not ok then log("error " .. tostring(err)) end
        end
      end
    end
  end
  r.defer(tick)
end

DEF = loadDefaults()
if not DEF then log("no settings file at " .. DEFAULTS) end
if NSM_SETTINGS_TEST then return { patch = patch, readLines = readLines } end
tick()
