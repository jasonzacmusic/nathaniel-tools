-- @description Palette & Look
-- @version 2.1.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about Colour and name your tracks from what they are: your own ordered rules
--   (import/export SWS Auto Color), instrument families with colours, palettes,
--   gradients and nudges, name-from-items, numbering, and a LIVE mode that
--   re-colours as tracks are added or renamed. Markers and regions too.
--   Requires the "Shared Libraries" package from this same repository
--   (right-click the repository in ReaPack > Install All).
-- @changelog
--   2.1.0 - first run imports your SWS Auto Color rules automatically; opens docked.
--   2.0.0 - new shared look (nt_ui): header, one status line + log, confirm
--           dialogs, system font, plain-English labels everywhere.
--           Status line now actually shows what happened (it never did).
--           "Selection" with nothing selected now says so instead of quietly
--           colouring the whole project.
--           Clear all rules / Import SWS / Export SWS / Clear colours and
--           Surprise on the whole project all ask first.
--           Export to SWS keeps every other line of sws-autocoloricon.ini
--           (icons, layouts, switches) and quotes multi-word filters.
--           "whole word" now matches a multi-word phrase; "wildcard" is a real
--           wildcard (* anything, ? one letter).
--           LIVE respects the Selection / Whole project choice, coalesces
--           bursts of changes (0.5 s), and re-fires on arm/mute changes.
--           Name + colour is one undo step; colouring markers from the button
--           is undoable; rule typing no longer re-scans the project per key.
--   1.0.0 - first public release. Crash-hardened (GUID identity + ValidatePtr2),
--           signature-based change detection, shared safety library.

--[[
  Palette & Look  -  REAPER / ReaImGui
  ------------------------------------------------------------------------------
  The colour / look / naming tool of the Nathaniel Tools.

  How a track gets its colour, in this order:

    1. MY RULES   an ordered list, first match wins - like SWS Auto Color but
                  with real match modes (contains / whole word / starts with /
                  exactly / wildcard / family / track type), a live mode, and
                  import/export of your existing sws-autocoloricon.ini.
    2. FAMILIES   synonym-aware fallback: "Gtr Dist L", "OD Rhythm" and
                  "Les Paul" all read as guitar without a rule.
    3. STRUCTURE  folders, buses and true FX returns (detected from receives
                  plus the plugins on the chain, not just the name).

  Plus: markers & regions coloured by the same rules, name-from-items,
  numbering, instrument emoji, palettes, gradients, lighter/darker/hue nudges,
  a Tracks tab showing now vs. wanted colour per track.
  One undo step per action.  Dockable.  Requires ReaImGui + Shared Libraries.
--]]

local r = reaper

--------------------------------------------------------------------------------
-- libraries
--------------------------------------------------------------------------------
do
  local sep = package.config:sub(1, 1)
  local here = ({ r.get_action_context() })[2]:match("(.*" .. sep .. ")") or ""
  package.path = here .. ".." .. sep .. "scripts" .. sep .. "lib" .. sep .. "?.lua;" ..
                 r.GetResourcePath() .. "/Scripts/Nathaniel Tools/scripts/lib/?.lua;" ..
                 package.path
end
local okSafe, safe = pcall(require, "nt_safe")
local okUi,   ui   = pcall(require, "nt_ui")
if not (okSafe and okUi) then
  r.ShowMessageBox("Palette & Look needs the 'Shared Libraries' package.\n\n" ..
    "Extensions > ReaPack > Browse packages > search 'Nathaniel Tools' > Shared Libraries > Install.\n" ..
    "(Or right-click the Nathaniel Tools repository > Install All.)", "Palette & Look", 0)
  return
end
do local ok, compat = pcall(require, "nt_imgui"); if ok then compat.install() end end
if not safe.require("Palette & Look", { imgui = true }) then return end

local APP = "Palette & Look"
local T = ui.tokens
math.randomseed(os.time())

local EXT    = "NSM_PaletteLook"
local SEP    = package.config:sub(1, 1)
local SWSINI = r.GetResourcePath() .. SEP .. "sws-autocoloricon.ini"

--------------------------------------------------------------------------------
-- palettes (from the theme adjuster)
--------------------------------------------------------------------------------
local PALETTES = {
  {name="REAPER",     cols={{84,84,84},{105,137,137},{129,137,137},{168,168,168},{19,189,153},{51,152,135},{184,143,63},{187,156,148},{134,94,82},{130,59,42}}},
  {name="WARM",       cols={{128,67,64},{184,82,46},{239,169,81},{230,204,143},{231,185,159},{208,193,180},{176,177,161},{108,120,116},{128,114,98},{97,87,74}}},
  {name="COOL",       cols={{35,75,84},{58,79,128},{95,88,128},{92,102,112},{67,104,128},{91,125,134},{95,92,85},{131,135,97},{55,118,94},{75,99,32}}},
  {name="VICE",       cols={{255,0,111},{255,89,147},{254,152,117},{255,202,193},{249,255,168},{122,242,178},{87,255,255},{51,146,255},{168,117,255},{99,77,196}}},
  {name="EEEK",       cols={{255,0,0},{255,111,0},{255,221,0},{179,255,0},{0,255,123},{0,213,255},{0,102,255},{93,0,255},{204,0,255},{255,0,153}}},
  {name="PRIDE",      cols={{84,84,84},{138,138,138},{155,55,55},{155,129,55},{105,155,55},{55,155,81},{55,155,155},{55,81,155},{105,55,155},{155,55,129}}},
  {name="CASABLANCA", cols={{166,42,0},{252,65,0},{252,114,28},{130,42,42},{156,81,50},{255,197,90},{148,134,108},{32,87,145},{65,91,128},{0,33,92}}},
  {name="CHAUFFEUR",  cols={{239,185,38},{153,91,0},{66,66,65},{119,120,120},{69,92,94},{59,77,92},{51,65,91},{41,49,97},{35,38,102},{97,45,74}}},
  {name="SPLIT",      cols={{255,0,64},{156,1,79},{129,22,74},{113,34,71},{96,47,68},{67,51,99},{49,49,104},{29,46,109},{0,39,107},{0,85,255}}},
  {name="NSM",        cols={{243,79,255},{182,48,50},{105,36,160},{255,241,76},{113,255,218},{90,200,255},{90,230,150},{235,175,60},{120,220,210},{200,110,255}}},
}

--------------------------------------------------------------------------------
-- families / synonyms (shared brain across the suite)
--------------------------------------------------------------------------------
local ROLE_ALIASES = {
  guitar   = {"guitar","gtr","electric","elec","dist","distortion","drive","overdrive","crunch","heavy","riff","strat","tele","lespaul"},
  acoustic = {"acoustic","aco","nylon","steel","folk"},
  bass     = {"bass","808","sub","dibox"},
  drums    = {"drum","drums","kit","kick","snare","snr","hat","hihat","tom","toms","floor","overhead","overheads","cymbal","ride","crash","perc","percussion","clap","shaker","conga","bongo","room","rooms","kik","beater","sub kick"},
  vocal    = {"vocal","vox","voice","lead vox","adlib"},
  harm     = {"harm","harmony","harmonies","bgv","bvs","stack","double","choir","gang"},
  keys     = {"keys","piano","pno","rhodes","wurli","wurlitzer","organ","clav","clavinet","harmonium"},
  synth    = {"synth","pad","pads","poly","arp","pluck"},
  strings  = {"strings","violin","cello","viola","orchestra"},
  brass    = {"brass","horn","horns","trumpet","sax","trombone"},
  wind     = {"flute","whistle","melodica","melodic","clarinet","oboe","recorder"},
}
-- short 2-3 letter tokens: only ever matched as a whole word, never as a substring
local ROLE_TOKENS = { ep="keys", ac="acoustic", od="guitar", gt="guitar", bs="bass",
                      oh="drums", ohs="drums", hh="drums", bd="drums", sd="drums",
                      rm="drums", tm="drums", cym="drums", bv="harm", bvs="harm",
                      ld="vocal", lv="vocal", ac_gtr="acoustic" }
-- Lua walks a hash table in whatever order it likes, which would make a name with
-- two family words ("Vox Stack") land differently from launch to launch. These two
-- lists pin the order: most specific family first, so "Acoustic Gtr" is acoustic
-- and "Vox Stack" is a harmony, the same way every single time.
local FAMILY_ORDER = { "acoustic", "harm", "drums", "bass", "guitar", "vocal",
                       "keys", "synth", "strings", "brass", "wind" }
local TOKEN_ORDER  = { "ac_gtr","ac","ep","od","gt","bs","oh","ohs","hh","bd","sd",
                       "rm","tm","cym","bv","bvs","ld","lv" }

-- names that really do mean "this is a bus / group / sum", matched as whole words.
-- (ALL-CAPS on its own is NOT enough: "OH L", "DI", "BGV" are not buses.)
local BUS_WORDS = {"bus","buss","busses","buses","grp","group","groups","submix",
                   "sub-mix","stem","stems","sum","summing","aux","vca","print",
                   "mixbus","master","masterbus","all"}
-- The emoji go INTO track names (REAPER shows them fine). The UI itself stays
-- ASCII because the window font draws emoji as "?".
local ROLE_EMOJI  = { guitar="🎸", acoustic="🪕", bass="🎸", drums="🥁", vocal="🎤", harm="🎙️", keys="🎹",
                      synth="🎛️", strings="🎻", brass="🎺", wind="🎶", ["return"]="💧", bus="📁" }
local ALL_EMOJI = { "🎸","🪕","🥁","🎤","🎙️","🎹","🎛️","🎻","🎺","🎶","🎚️","💧","🟨","📁" }

local FX_WORDS = {"verb","reverb","rvb","delay","dly","echo","slap","plate","hall",
                  "chamber","spring","space","fx","send","return","rtn","ambience","ambient"}
local FX_PLUGINS = {"valhalla","reverb","verb","delay","echo","lexicon","emt","plate","raum",
                    "blackhole","shimmer","convolution","spaces","cinematic rooms","pro-r","h-delay","h-reverb"}

local ROLE_ORDER = { "guitar","acoustic","bass","drums","vocal","harm","keys","synth","strings","brass","wind","return","bus" }

-- what a musician sees for each family key
local FAMILY_LABEL = { guitar="Guitar", acoustic="Acoustic", bass="Bass", drums="Drums", vocal="Vocal",
                       harm="Harmony", keys="Keys", synth="Synth", strings="Strings", brass="Brass",
                       wind="Winds", ["return"]="FX return", bus="Bus" }
-- typed family names (in a "family" rule) -> family key
local FAMILY_LOOKUP = {}
for k, lbl in pairs(FAMILY_LABEL) do FAMILY_LOOKUP[k] = k; FAMILY_LOOKUP[lbl:lower()] = k end
FAMILY_LOOKUP["harmonies"] = "harm"; FAMILY_LOOKUP["wind"] = "wind"; FAMILY_LOOKUP["vocals"] = "vocal"
FAMILY_LOOKUP["return"] = "return"; FAMILY_LOOKUP["returns"] = "return"; FAMILY_LOOKUP["fx returns"] = "return"
local function familyKey(f) return FAMILY_LOOKUP[(f or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")] end

--------------------------------------------------------------------------------
-- FAMILY colours.  Defaults are Jason's real colours, read out of his own
-- sws-autocoloricon.ini, so this app starts where the muscle memory already is.
--------------------------------------------------------------------------------
local DEFAULTS = {
  guitar   = {243, 79,255},   -- 0xF34FFF  SWS "Guitar"
  bass     = {182, 48, 50},   -- 0xB63032  SWS "Bass"
  harm     = {105, 36,160},   -- 0x6924A0  SWS "Harm"
  ["return"] = {255,241, 76}, -- 0xFFF14C  SWS "(receive)" - sends come back yellow
  bus      = {113,255,218},   -- 0x71FFDA  mint folders
  acoustic = {255,150, 90},
  drums    = {225, 70, 70},
  vocal    = { 90,200,255},
  keys     = { 90,230,150},
  synth    = {200,110,255},
  strings  = {150,190,120},
  brass    = {235,175, 60},
  wind     = {120,220,210},
}
local RULES = {}
for k, v in pairs(DEFAULTS) do RULES[k] = { v[1], v[2], v[3] } end

local function saveRules()
  for k, c in pairs(RULES) do
    r.SetExtState(EXT, "rule_" .. k, string.format("%d,%d,%d", c[1], c[2], c[3]), true)
  end
end
local function loadRules()
  for k, _ in pairs(RULES) do
    local s = r.GetExtState(EXT, "rule_" .. k)
    if s and s ~= "" then
      local a, b, c = s:match("(%d+),(%d+),(%d+)")
      if a then RULES[k] = { tonumber(a), tonumber(b), tonumber(c) } end
    end
  end
end
loadRules()

--------------------------------------------------------------------------------
-- MY RULES : the SWS-style ordered filter table, but smarter
--   { on, kind="track"|"marker"|"region", mode, filter, rgb={r,g,b} }
--------------------------------------------------------------------------------
-- internal ids (stored) and the words a musician sees for them
local MODES       = { "contains", "word", "starts", "exact", "pattern", "role", "special" }
local MODE_LABELS = { "contains", "whole word", "starts with", "exactly", "wildcard", "family", "track type" }
local MODE_TIP =
  "How the text is matched against the name:\n" ..
  "  contains     - the text appears anywhere (* = anything)\n" ..
  "  whole word   - the text as a whole word or phrase, not inside another word\n" ..
  "  starts with  - the name begins with the text\n" ..
  "  exactly      - the whole name is the text\n" ..
  "  wildcard     - whole name, where * = anything and ? = one letter\n" ..
  "  family       - the track's instrument family: Drums, Guitar, Bass, Vocal, Harmony, Keys, Synth, Strings, Brass, Winds, Acoustic\n" ..
  "  track type   - type one of these as the text:\n" ..
  "     (folder) folder parents   (receive) gets sends from other tracks\n" ..
  "     (send) sends to others    (master) the master track\n" ..
  "     (unnamed) no name yet     (any) every track\n" ..
  "     (armed) record-armed      (muted) muted\n" ..
  "     (empty) no items          (midi) has MIDI items\n" ..
  "Capital letters never matter."
local KINDS       = { "track", "marker", "region" }
local KIND_LABELS = { "Tracks", "Markers", "Regions" }
local function modeIdx(id) for i, m in ipairs(MODES) do if m == id then return i end end return 1 end
local function kindIdx(id) for i, k in ipairs(KINDS) do if k == id then return i end end return 1 end
local function modeLabel(id) return MODE_LABELS[modeIdx(id)] end
local function kindLabel(id) return KIND_LABELS[kindIdx(id)] end

local MYRULES = {}

local function rulesSerialize()
  local out = {}
  for _, ru in ipairs(MYRULES) do
    out[#out + 1] = table.concat({ ru.on and 1 or 0, ru.kind, ru.mode,
      (ru.filter:gsub("|", "/")), string.format("%02X%02X%02X", ru.rgb[1], ru.rgb[2], ru.rgb[3]) }, "|")
  end
  return table.concat(out, "\n")
end
local function rulesSave()
  r.SetExtState(EXT, "myrules", rulesSerialize(), true)
  r.SetExtState(EXT, "myrules_n", tostring(#MYRULES), true)
end
local function rulesLoad()
  local s = r.GetExtState(EXT, "myrules")
  MYRULES = {}
  if not s or s == "" then return end
  for line in s:gmatch("[^\n]+") do
    local on, kind, mode, filter, hex = line:match("^(%d)|([^|]*)|([^|]*)|([^|]*)|(%x%x%x%x%x%x)$")
    if on then
      MYRULES[#MYRULES + 1] = { on = on == "1", kind = kind, mode = mode, filter = filter,
        rgb = { tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16) } }
    end
  end
end
rulesLoad()

--------------------------------------------------------------------------------
-- SWS ini import / export
--------------------------------------------------------------------------------
local function readFile(p) local f = io.open(p, "rb"); if not f then return nil end local c = f:read("*a"); f:close(); return c end
local function splitLines(txt) local t = {} for l in (txt .. "\n"):gmatch("(.-)\r?\n") do t[#t + 1] = l end return t end

-- One "AutoColor n=<type> <filter> <colour> "icon" "layout" "layout2"" line ->
-- typ, filter, colour, extra (the trailing quoted fields, kept verbatim).
local function parseSWSLine(line)
  local body = line:match("^AutoColor%s*%d+%s*=%s*(.+)$")
  if not body then return nil end
  local typ, rest = body:match("^(%d+)%s+(.*)$")
  if not typ then return nil end
  local filter, after
  local q = rest:sub(1, 1)
  if q == '"' or q == "'" or q == "`" then
    filter, after = rest:match("^" .. q .. "([^" .. q .. "]*)" .. q .. "%s*(.*)$")
  else
    filter, after = rest:match("^(%S+)%s*(.*)$")
  end
  if not filter then return nil end
  local col, extra = (after or ""):match("^(%-?%d+)%s*(.*)$")
  if not col then return nil end
  return typ, filter, tonumber(col), extra or ""
end

-- Read the SWS file into a rule list WITHOUT touching MYRULES.
local function scanSWS()
  local txt = readFile(SWSINI)
  if not txt then return nil, "No SWS Auto Color file found (" .. SWSINI .. ")." end
  local imported = {}
  for _, line in ipairs(splitLines(txt)) do
    local typ, filter, col = parseSWSLine(line)
    if typ then
      local rgb = { (col >> 16) & 0xFF, (col >> 8) & 0xFF, col & 0xFF }
      local kind = (typ == "1") and "marker" or (typ == "2") and "region" or "track"
      -- SWS itself does a case-insensitive substring match (with * wildcards),
      -- so import as "contains" to reproduce the existing behaviour exactly.
      local mode = "contains"
      if filter:sub(1, 1) == "(" then mode = "special" end
      imported[#imported + 1] = { on = true, kind = kind, mode = mode, filter = filter, rgb = rgb }
    end
  end
  if #imported == 0 then return nil, "Found the SWS file but no Auto Color rules in it." end
  return imported
end

local function importSWS(list)
  MYRULES = list
  rulesSave()
  return #list
end

-- First run on a machine: start from the SWS Auto Color rules already there, so
-- the colours you know (and your V / C / B marker colours) are the colours this
-- app uses from the first click. Done once; "Import my SWS rules" redoes it.
local autoImportedNow = 0
if #MYRULES == 0 and r.GetExtState(EXT, "sws_autoimported") ~= "1" then
  local list = scanSWS()
  if list and #list > 0 then autoImportedNow = importSWS(list) end
  r.SetExtState(EXT, "sws_autoimported", "1", true)
end

-- WDL-style quoting: bare when the filter has no spaces or quotes.
local function swsQuote(s)
  if s == "" then return '""' end
  if not s:find("[%s\"']") then return s end
  if not s:find('"') then return '"' .. s .. '"' end
  if not s:find("'") then return "'" .. s .. "'" end
  return "`" .. s .. "`"
end

-- Rewrites ONLY the AutoColor rules in sws-autocoloricon.ini.  Every other
-- line (AutoIcon*, AutoLayout*, anything else) is kept where it was.  Icon /
-- layout fields of an existing rule with the same type+filter are carried over.
-- A backup of the previous file is written beside it first.
local function exportSWS()
  local bak = SWSINI .. ".paletteBackup"
  local cur = readFile(SWSINI)
  if cur then local f = io.open(bak, "wb"); if f then f:write(cur); f:close() end end

  local kept, extras, insertAt = {}, {}, nil
  local sawSection = false
  local skipKeys = { AutoColorCount = true, AutoColorEnable = true, AutoColorMarkerEnable = true, AutoColorRegionEnable = true }
  for _, line in ipairs(splitLines(cur or "")) do
    local typ, filter, _, extra = parseSWSLine(line)
    local key = line:match("^(%w+)%s*=")
    if typ then
      if extra ~= "" then extras[typ .. ":" .. filter:lower()] = extra end
      if not insertAt then insertAt = #kept + 1 end
    elseif key and skipKeys[key] then
      if not insertAt then insertAt = #kept + 1 end
    else
      kept[#kept + 1] = line
      if line:match("^%[SWS%]") then sawSection = true; if not insertAt then insertAt = #kept + 1 end end
    end
  end
  while #kept > 0 and kept[#kept]:match("^%s*$") do kept[#kept] = nil end
  if not sawSection then table.insert(kept, 1, "[SWS]"); insertAt = 2 end
  if not insertAt then insertAt = #kept + 1 end

  local block, n = {}, 0
  for _, ru in ipairs(MYRULES) do
    n = n + 1
    local typ = (ru.kind == "marker") and 1 or (ru.kind == "region") and 2 or 0
    local col = 0x02000000 | (ru.rgb[1] << 16) | (ru.rgb[2] << 8) | ru.rgb[3]
    local extra = extras[typ .. ":" .. ru.filter:lower()] or '"" "" ""'
    block[#block + 1] = string.format('AutoColor %d=%d %s %d %s', n, typ, swsQuote(ru.filter), col, extra)
  end
  block[#block + 1] = "AutoColorCount=" .. n
  block[#block + 1] = "AutoColorEnable=1"
  block[#block + 1] = "AutoColorMarkerEnable=1"
  block[#block + 1] = "AutoColorRegionEnable=1"

  local out = {}
  for i = 1, insertAt - 1 do out[#out + 1] = kept[i] end
  for _, l in ipairs(block) do out[#out + 1] = l end
  for i = insertAt, #kept do out[#out + 1] = kept[i] end

  local f = io.open(SWSINI, "wb")
  if not f then return nil, "Could not write " .. SWSINI end
  f:write(table.concat(out, "\n") .. "\n"); f:close()
  return n, bak
end

--------------------------------------------------------------------------------
-- matching
--------------------------------------------------------------------------------
local function roleOf(name)
  local low = name:lower()
  local toks = {}
  for t in low:gmatch("[%w']+") do toks[t] = true end
  -- pass 1: exact short tokens ("oh", "bv", "ep") -- always whole words
  for _, tk in ipairs(TOKEN_ORDER) do
    if toks[tk] then return ROLE_TOKENS[tk] end
  end
  -- pass 2: whole-word alias, families walked in a FIXED order so the same
  -- name always lands on the same family, on every machine, every launch
  for _, role in ipairs(FAMILY_ORDER) do
    for _, w in ipairs(ROLE_ALIASES[role] or {}) do
      if toks[w] then return role end
    end
  end
  -- pass 3: only now allow a loose substring, same fixed order
  for _, role in ipairs(FAMILY_ORDER) do
    for _, w in ipairs(ROLE_ALIASES[role] or {}) do
      if #w >= 4 and low:find(w, 1, true) then return role end
    end
  end
  return nil
end
local function isBusName(name)
  if name == "" then return false end
  local toks = {}
  for w in name:lower():gmatch("[%w'%-]+") do toks[w] = true end
  for _, w in ipairs(BUS_WORDS) do if toks[w] then return true end end
  return false
end
local function isFolder(t) return r.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH") == 1 end
local function nameSaysFX(name)
  local low = " " .. name:lower() .. " "
  for _, w in ipairs(FX_WORDS) do
    if low:find("%f[%w]" .. w:gsub("%-", "%%-") .. "%f[%W]") then return true end
  end
  return false
end
local function fxChainSaysFX(t)
  for i = 0, r.TrackFX_GetCount(t) - 1 do
    local ok, nm = r.TrackFX_GetFXName(t, i, "")
    if ok and nm then
      local low = nm:lower()
      for _, w in ipairs(FX_PLUGINS) do if low:find(w, 1, true) then return true end end
    end
  end
  return false
end
local tName = safe.trackName
local function isReturn(t)
  local recv = r.GetTrackNumSends(t, -1)
  local nm = select(2, r.GetSetMediaTrackInfo_String(t, "P_NAME", "", false)) or ""
  if recv and recv > 0 then
    if nameSaysFX(nm) or fxChainSaysFX(t) then return true end
  end
  if nameSaysFX(nm) and fxChainSaysFX(t) then return true end
  return false
end

local function escapePat(s) return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end
-- wildcard -> anchored Lua pattern.  * = anything; ? = one character when
-- `qmark` is set (the "wildcard" mode), literal otherwise (the "contains" mode).
local function wildToPattern(f, qmark)
  local p = f:gsub("[%^%$%(%)%%%.%[%]%+%-]", "%%%0")
  if qmark then p = p:gsub("%?", ".") else p = p:gsub("%?", "%%?") end
  p = p:gsub("%*", ".*")
  return "^" .. p .. "$"
end
-- whole-word match of a whole phrase: "lead vox" matches "Lead Vox 2" but not
-- "Leader Voxbox".
local function wholeWordIn(low, f)
  local pre  = f:sub(1, 1):match("[%w']") and "%f[%w']" or ""
  local post = f:sub(-1):match("[%w']") and "%f[^%w']" or ""
  return low:find(pre .. escapePat(f) .. post) ~= nil
end

local function ruleMatchesName(ru, name)
  local low, f = name:lower(), ru.filter:lower()
  if f == "" then return false end
  if ru.mode == "contains" then
    if f:find("%*") then return low:find(wildToPattern(f, false)) ~= nil end
    return low:find(f, 1, true) ~= nil
  elseif ru.mode == "word" then
    return wholeWordIn(low, f)
  elseif ru.mode == "starts" then
    return low:sub(1, #f) == f
  elseif ru.mode == "exact" then
    return low == f
  elseif ru.mode == "pattern" then
    -- an advanced Lua pattern saved by an older version (has a % escape) still works
    if ru.filter:find("%%") then
      local ok, res = pcall(string.find, low, ru.filter)
      return ok and res ~= nil
    end
    return low:find(wildToPattern(f, true)) ~= nil
  elseif ru.mode == "role" then
    local k = familyKey(f)
    return k ~= nil and roleOf(name) == k
  end
  return false
end

local function ruleMatchesTrack(ru, t, name)
  if ru.mode == "special" or ru.filter:sub(1, 1) == "(" then
    local s = ru.filter:lower()
    if s == "(folder)"  then return isFolder(t) end
    if s == "(receive)" then local n = r.GetTrackNumSends(t, -1); return n and n > 0 end
    if s == "(send)"    then local n = r.GetTrackNumSends(t, 0);  return n and n > 0 end
    if s == "(master)"  then return t == r.GetMasterTrack(0) end
    if s == "(unnamed)" then local ok, nm = r.GetSetMediaTrackInfo_String(t, "P_NAME", "", false); return not ok or nm == "" end
    if s == "(any)"     then return true end
    if s == "(armed)"   then return r.GetMediaTrackInfo_Value(t, "I_RECARM") == 1 end
    if s == "(muted)"   then return r.GetMediaTrackInfo_Value(t, "B_MUTE") == 1 end
    if s == "(empty)"   then return r.CountTrackMediaItems(t) == 0 end
    if s == "(midi)"    then
      for i = 0, r.CountTrackMediaItems(t) - 1 do
        local tk = r.GetActiveTake(r.GetTrackMediaItem(t, i))
        if tk and r.TakeIsMIDI(tk) then return true end
      end
      return false
    end
    return false
  end
  return ruleMatchesName(ru, name)
end

--------------------------------------------------------------------------------
-- colour helpers
--------------------------------------------------------------------------------
local function clamp(v) return math.max(0, math.min(255, math.floor(v + 0.5))) end
local function setCol(t, rgb) r.SetTrackColor(t, r.ColorToNative(clamp(rgb[1]), clamp(rgb[2]), clamp(rgb[3]))) end
local function u32(rgb) return (clamp(rgb[1]) << 24) | (clamp(rgb[2]) << 16) | (clamp(rgb[3]) << 8) | 0xff end
local function getRGB(t)
  local c = r.GetTrackColor(t); if c == 0 then return nil end
  local a, b, d = r.ColorFromNative(c); return { a, b, d }
end
local function shade(rgb, f)
  local function m(c) if f >= 0 then return c + (255 - c) * f else return c * (1 + f) end end
  return { m(rgb[1]), m(rgb[2]), m(rgb[3]) }
end
local function randRGB() return { math.random(60, 255), math.random(60, 255), math.random(60, 255) } end
local function rgb2hsl(c)
  local R, G, B = c[1] / 255, c[2] / 255, c[3] / 255
  local mx, mn = math.max(R, G, B), math.min(R, G, B)
  local h, s, l = 0, 0, (mx + mn) / 2
  if mx ~= mn then
    local d = mx - mn
    s = l > 0.5 and d / (2 - mx - mn) or d / (mx + mn)
    if mx == R then h = (G - B) / d + (G < B and 6 or 0) elseif mx == G then h = (B - R) / d + 2 else h = (R - G) / d + 4 end
    h = h / 6
  end
  return h, s, l
end
local function hsl2rgb(h, s, l)
  local function hue(p, q, t)
    if t < 0 then t = t + 1 end; if t > 1 then t = t - 1 end
    if t < 1 / 6 then return p + (q - p) * 6 * t end
    if t < 1 / 2 then return q end
    if t < 2 / 3 then return p + (q - p) * (2 / 3 - t) * 6 end
    return p
  end
  if s == 0 then return { l * 255, l * 255, l * 255 } end
  local q = l < 0.5 and l * (1 + s) or l + s - l * s
  local p = 2 * l - q
  return { hue(p, q, h + 1 / 3) * 255, hue(p, q, h) * 255, hue(p, q, h - 1 / 3) * 255 }
end
local function lerp(a, b, f) return { a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f } end
local function hexOf(c) return string.format("#%02X%02X%02X", clamp(c[1]), clamp(c[2]), clamp(c[3])) end
local function packRGB(c) return (clamp(c[1]) << 16) | (clamp(c[2]) << 8) | clamp(c[3]) end
local function unpackRGB(v) return { (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF } end
local function baseKey(name)
  local s = name:lower():gsub("[^%a]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  return (s:gsub("%s+[lr]$", ""))
end

--------------------------------------------------------------------------------
-- state
--------------------------------------------------------------------------------
local ctx = r.ImGui_CreateContext(APP)
ui.fonts(ctx)
if autoImportedNow > 0 then ui.say(ctx, ("First run: took over your %d SWS Auto Color rule(s) and your SWS family colours."):format(autoImportedNow), "ok") end

local paletteIdx  = 10
local scope       = "sel"          -- "sel" | "all"
local rows        = {}             -- { guid, name, kind, label, want, depth, sel }
-- Resync trigger. NOT GetProjectStateChangeCount - measured in REAPER 7.77, that
-- counter does NOT move when a track is inserted, renamed or deleted, so any
-- watchdog built on it never fires. We compare a cheap signature of the track
-- list instead (nt_safe.projSignature + arm/mute state). See loop().
local lastSig, lastSigT = nil, 0
local shadeChildren = true
local numberTracks, numberStart = false, 1
local useMyRules   = true
local doMarkers    = true
local liveOn       = false
local liveSig, liveApplyT = "", 0
local gradA, gradB = { 243, 79, 255 }, { 90, 200, 255 }
local newFilter, newModeIdx, newKindIdx = "", 1, 1
local newRGB = { 200, 120, 255 }
local dirtyT = nil                 -- rules / family colours edited; flushed 0.4 s after the last edit
local tableDrawn = false           -- a table already sized itself to leave room for the footer this frame
local pendingImport = nil          -- rule list scanned from SWS, waiting for the confirm

local NOIN = ui.E("ColorEditFlags_NoInputs") or 0

local function say(msg, level) ui.say(ctx, msg, level) end
local function markDirty() dirtyT = r.time_precise() end

-- Arm + mute per track, so a rule on (armed) / (muted) re-fires in LIVE mode.
local function armMuteSig()
  local acc = {}
  for i = 0, r.CountTracks(0) - 1 do
    local t = r.GetTrack(0, i)
    if t then
      acc[#acc + 1] = math.floor(r.GetMediaTrackInfo_Value(t, "I_RECARM") or 0) ..
                      math.floor(r.GetMediaTrackInfo_Value(t, "B_MUTE") or 0)
    end
  end
  return table.concat(acc)
end
local function fullSig() return safe.projSignature(0) .. "#" .. armMuteSig() end

-- The tracks an action works on.  nil = nothing to do (and it has been said).
-- Pointers in this list are used inside the same call only, never kept.
local function scopeList(quiet)
  local t = {}
  if scope == "sel" then
    for i = 0, r.CountSelectedTracks(0) - 1 do t[#t + 1] = r.GetSelectedTrack(0, i) end
    if #t == 0 then
      if not quiet then say("Nothing selected - select tracks or switch to Whole project.", "warn") end
      return nil
    end
  else
    for i = 0, r.CountTracks(0) - 1 do t[#t + 1] = r.GetTrack(0, i) end
    if #t == 0 then
      if not quiet then say("No tracks in this project yet.", "warn") end
      return nil
    end
  end
  return t
end
local function scopeWord() return scope == "sel" and "the selection" or "the whole project" end

-- the whole decision, in one place.  Returns rgb, why
--   why = "rule:<n>" | "return" | "group:<family>" | "bus" | <family key> | nil
local function decide(t, name)
  if useMyRules then
    for i, ru in ipairs(MYRULES) do
      if ru.on and ru.kind == "track" and ruleMatchesTrack(ru, t, name) then
        return ru.rgb, "rule:" .. i
      end
    end
  end
  -- a return is a return, whatever it is called
  if isReturn(t) then return RULES["return"], "return" end
  local role  = roleOf(name)
  -- a folder parent, or a track whose name literally says bus / group / stem
  local group = isFolder(t) or isBusName(name)
  -- a group that says what it holds wears that family one shade deeper, so
  -- DRUMS reads as the dark red parent of its red kit instead of a mint slab,
  -- and "Drum Bus" sits with the drums rather than pretending to be a track
  if group and role and RULES[role] then return shade(RULES[role], -0.32), "group:" .. role end
  if group then return RULES.bus, "bus" end
  if role and RULES[role] then return RULES[role], role end
  return nil, nil
end
local function isStructural(why) return why == "bus" or why == "return" or why:sub(1, 6) == "group:" end

-- what the Tracks tab and the status line call a decision
local function whyLabel(why)
  if not why then return "-" end
  local n = why:match("^rule:(%d+)$")
  if n then local ru = MYRULES[tonumber(n)]; return "Rule: " .. (ru and ru.filter or "?") end
  local g = why:match("^group:(.+)$")
  if g then return "Bus: " .. (FAMILY_LABEL[g] or g) end
  if why == "bus" then return "Folder / bus" end
  if why == "return" then return "FX return" end
  return "Family: " .. (FAMILY_LABEL[why] or why)
end

-- Rows store the GUID, which survives delete / undo / reorder / reload; the
-- pointer is resolved and validated immediately before every use.
local function rebuild()
  rows = {}
  for i = 0, r.CountTracks(0) - 1 do
    local t = r.GetTrack(0, i)
    if t then
      local nm = tName(t)
      local rgb, why = decide(t, nm)
      rows[#rows + 1] = { guid = r.GetTrackGUID(t), name = nm, kind = why, label = whyLabel(why), want = rgb,
                          depth = r.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH"), sel = r.IsTrackSelected(t) }
    end
  end
end

-- Resolve one row to a validated, live pointer.  nil is a normal answer: it
-- means the user deleted that track and the row is now a tombstone.
local function rowTrack(row, map)
  local t = map and map[row.guid] or nil
  if safe.trackAlive(0, t) then return t end
  return nil
end

local function pcol(i) local c = PALETTES[paletteIdx].cols; return c[((i - 1) % #c) + 1] end
local function refreshUI() r.TrackList_AdjustWindows(false); r.UpdateArrange() end

--------------------------------------------------------------------------------
-- markers & regions
--------------------------------------------------------------------------------
local function paintMarkers()
  local i, painted, total = 0, 0, 0
  while true do
    local ok, isrgn, pos, rgnend, name, idx = r.EnumProjectMarkers3(0, i)
    if not ok or ok == 0 then break end
    total = total + 1
    local kind = isrgn and "region" or "marker"
    for _, ru in ipairs(MYRULES) do
      if ru.on and ru.kind == kind and ruleMatchesName(ru, name or "") then
        local native = r.ColorToNative(clamp(ru.rgb[1]), clamp(ru.rgb[2]), clamp(ru.rgb[3])) | 0x1000000
        r.SetProjectMarkerByIndex2(0, i, isrgn, pos, rgnend, idx, name, native, 0)
        painted = painted + 1
        break
      end
    end
    i = i + 1
  end
  return painted, total
end
local function applyMarkers()
  r.Undo_BeginBlock2(0)
  local painted, total = paintMarkers()
  r.Undo_EndBlock2(0, "Palette & Look: colour markers and regions", -1)
  r.UpdateArrange()
  if total == 0 then say("No markers or regions in this project.", "warn")
  elseif painted == 0 then say(("Markers and regions: none of the %d matched a marker/region rule."):format(total), "warn")
  else say(("Markers and regions: coloured %d of %d."):format(painted, total), "ok") end
end

--------------------------------------------------------------------------------
-- MODE 1: the rule engine
--   o = { list=, undo=(default true), silent=, quiet= }
--------------------------------------------------------------------------------
local function applyRules(o)
  o = o or {}
  local list = o.list or scopeList(o.quiet)
  if not list then return 0 end
  if o.undo ~= false then r.Undo_BeginBlock2(0) end
  local famOf, stack = {}, {}
  for i = 0, r.CountTracks(0) - 1 do
    local t = r.GetTrack(0, i)
    local d = r.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH")
    if #stack > 0 then famOf[t] = stack[#stack] end
    if d == 1 then stack[#stack + 1] = { top = t, n = {} } end
    if d < 0 then for _ = 1, -d do if #stack > 0 then table.remove(stack) end end end
  end
  local counts, order, painted, unknown = {}, {}, 0, {}
  for _, t in ipairs(list) do
    local nm = tName(t)
    local c, why = decide(t, nm)
    if c then
      if not isStructural(why) and shadeChildren and famOf[t] then
        -- siblings of the SAME family inside a folder step gently lighter,
        -- so a kit reads as one colour with depth instead of five flat blocks
        local f = famOf[t]
        f.n[why] = (f.n[why] or 0) + 1
        c = shade(c, math.min(0.045 * ((f.n[why] - 1) % 5), 0.18))
      end
      setCol(t, c); painted = painted + 1
      local lbl = whyLabel(why)
      if not counts[lbl] then order[#order + 1] = lbl end
      counts[lbl] = (counts[lbl] or 0) + 1
    else
      unknown[#unknown + 1] = nm
    end
  end
  local mk = doMarkers and paintMarkers() or 0
  if o.undo ~= false then r.Undo_EndBlock2(0, "Palette & Look: apply colours", -1) end
  refreshUI()
  if not o.silent then
    local parts = {}
    for _, lbl in ipairs(order) do parts[#parts + 1] = lbl .. " " .. counts[lbl] end
    local msg = ("Coloured %d track(s) in %s%s."):format(painted, scopeWord(), mk > 0 and (" + " .. mk .. " marker(s)/region(s)") or "")
    if #parts > 0 then msg = msg .. "  " .. table.concat(parts, ", ") end
    if #unknown > 0 then
      local u = {}
      for i = 1, math.min(#unknown, 6) do u[#u + 1] = unknown[i] end
      msg = msg .. ("  Nothing matched %d: %s%s"):format(#unknown, table.concat(u, ", "), #unknown > 6 and " ..." or "")
    end
    say(msg, painted > 0 and "ok" or "warn")
  end
  rebuild()
  return painted
end

--------------------------------------------------------------------------------
-- palettes
--------------------------------------------------------------------------------
local function applyByRole()
  local list = scopeList(); if not list then return end
  r.Undo_BeginBlock2(0)
  local map, idx = {}, 0
  for _, t in ipairs(list) do
    local nm = tName(t)
    local key = select(2, decide(t, nm)) or ("~" .. baseKey(nm))
    if not map[key] then idx = idx + 1; map[key] = pcol(idx) end
    setCol(t, map[key])
  end
  r.Undo_EndBlock2(0, "Palette & Look: colour by family", -1)
  refreshUI()
  say(("Coloured %d track(s) by family with the %s palette (%d colours used)."):format(#list, PALETTES[paletteIdx].name, idx), "ok")
  rebuild()
end

-- structural: always walks the whole project (it needs the folder tree)
local function applyByFolder()
  if r.CountTracks(0) == 0 then say("No tracks in this project yet.", "warn"); return end
  r.Undo_BeginBlock2(0)
  local stack, fam = {}, 0
  for i = 0, r.CountTracks(0) - 1 do
    local t = r.GetTrack(0, i)
    local nm = tName(t)
    local d = r.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH")
    if d == 1 or (isBusName(nm) and d >= 1) then
      fam = fam + 1
      local c = pcol(fam)
      setCol(t, c)
      if d == 1 then stack[#stack + 1] = { c = c, n = 0 } end
    else
      if #stack > 0 then
        local top = stack[#stack]
        setCol(t, shade(top.c, math.min(0.10 + top.n * 0.09, 0.6)))
        top.n = top.n + 1
      else
        setCol(t, pcol(fam + 1))
      end
    end
    if d < 0 then for _ = 1, -d do if #stack > 0 then table.remove(stack) end end end
  end
  r.Undo_EndBlock2(0, "Palette & Look: colour by folder", -1)
  refreshUI()
  say(("Coloured by folder: %d folder(s) each got a %s colour, their tracks lighter shades of it."):format(fam, PALETTES[paletteIdx].name), "ok")
  rebuild()
end

local function applySurprise()
  local list = scopeList(); if not list then return end
  r.Undo_BeginBlock2(0)
  local g = {}
  for _, t in ipairs(list) do
    local k = baseKey(tName(t))
    if not g[k] then g[k] = randRGB() end
    setCol(t, g[k])
  end
  r.Undo_EndBlock2(0, "Palette & Look: surprise colours", -1)
  refreshUI()
  say(("Surprise! %d track(s) got random colours (same names share one). Press again to re-roll."):format(#list), "ok")
  rebuild()
end

local function applyPaletteInOrder()
  local list = scopeList(); if not list then return end
  r.Undo_BeginBlock2(0)
  for i, t in ipairs(list) do setCol(t, pcol(i)) end
  r.Undo_EndBlock2(0, "Palette & Look: palette in order", -1)
  refreshUI()
  say(("Applied the %s palette across %d track(s), in track order."):format(PALETTES[paletteIdx].name, #list), "ok")
  rebuild()
end

--------------------------------------------------------------------------------
-- tools
--------------------------------------------------------------------------------
local function applyGradient()
  local list = scopeList(); if not list then return end
  r.Undo_BeginBlock2(0)
  for i, t in ipairs(list) do
    local f = (#list < 2) and 0 or (i - 1) / (#list - 1)
    setCol(t, lerp(gradA, gradB, f))
  end
  r.Undo_EndBlock2(0, "Palette & Look: gradient", -1)
  refreshUI()
  say(("Gradient %s -> %s across %d track(s)."):format(hexOf(gradA), hexOf(gradB), #list), "ok"); rebuild()
end

local NUDGE_WORD = { light = "brightness", sat = "colour strength", hue = "hue" }
local function nudge(kind, amt)
  local list = scopeList(); if not list then return end
  r.Undo_BeginBlock2(0)
  local n = 0
  for _, t in ipairs(list) do
    local c = getRGB(t)
    if c then
      local h, s, l = rgb2hsl(c)
      if kind == "light" then l = math.max(0, math.min(1, l + amt))
      elseif kind == "sat" then s = math.max(0, math.min(1, s + amt))
      elseif kind == "hue" then h = (h + amt) % 1 end
      setCol(t, hsl2rgb(h, s, l)); n = n + 1
    end
  end
  r.Undo_EndBlock2(0, "Palette & Look: nudge colour", -1)
  refreshUI()
  if n == 0 then say("No coloured tracks in " .. scopeWord() .. " to nudge - colour them first.", "warn")
  else say(("Nudged %s on %d track(s)."):format(NUDGE_WORD[kind] or kind, n), "ok") end
  rebuild()
end

local function copyFirstColor()
  local list = scopeList(); if not list then return end
  if #list < 2 then say("Select at least two tracks: the first one's colour goes onto the rest.", "warn"); return end
  local c = getRGB(list[1])
  if not c then say(("The first track (%s) has no colour to copy."):format(tName(list[1])), "warn"); return end
  r.Undo_BeginBlock2(0)
  for i = 2, #list do setCol(list[i], c) end
  r.Undo_EndBlock2(0, "Palette & Look: match colour", -1)
  refreshUI()
  say(("Matched %d track(s) to %s (%s)."):format(#list - 1, tName(list[1]), hexOf(c)), "ok"); rebuild()
end

-- structural: whole project (needs the folder tree)
local function inheritFromParent()
  if r.CountTracks(0) == 0 then say("No tracks in this project yet.", "warn"); return end
  r.Undo_BeginBlock2(0)
  local stack, n = {}, 0
  for i = 0, r.CountTracks(0) - 1 do
    local t = r.GetTrack(0, i)
    local d = r.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH")
    if #stack > 0 then
      local top = stack[#stack]
      setCol(t, shade(top.c, math.min(0.08 + top.n * 0.08, 0.55))); top.n = top.n + 1; n = n + 1
    end
    if d == 1 then local c = getRGB(t) or pcol(i + 1); stack[#stack + 1] = { c = c, n = 0 } end
    if d < 0 then for _ = 1, -d do if #stack > 0 then table.remove(stack) end end end
  end
  r.Undo_EndBlock2(0, "Palette & Look: children inherit folder colour", -1)
  refreshUI()
  if n == 0 then say("No folders in this project, so nothing to inherit from.", "warn")
  else say(("%d track(s) now wear a lighter shade of their folder's colour."):format(n), "ok") end
  rebuild()
end

local function clearColors()
  local list = scopeList(); if not list then return end
  r.Undo_BeginBlock2(0)
  for _, t in ipairs(list) do r.SetTrackColor(t, 0) end
  r.Undo_EndBlock2(0, "Palette & Look: clear colours", -1)
  refreshUI()
  say(("Cleared the colour on %d track(s) in %s."):format(#list, scopeWord()), "ok"); rebuild()
end

--------------------------------------------------------------------------------
-- naming
--------------------------------------------------------------------------------
local function prettify(s)
  s = s:gsub("%.[%a%d]+$", "")
  s = s:gsub("^%s*%d+%s*[%-_%.%)]?%s*", "")
  s = s:gsub("[_%-]+", " ")
  s = s:gsub("%s*%d+%s*$", "")
  return (s:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""))
end
-- o = { list=, undo=(default true), silent= }
local function nameFromItems(o)
  o = o or {}
  local list = o.list or scopeList()
  if not list then return 0 end
  if o.undo ~= false then r.Undo_BeginBlock2(0) end
  local num, renamed = numberStart, 0
  for _, t in ipairs(list) do
    local newName
    if r.CountTrackMediaItems(t) > 0 then
      local tk = r.GetActiveTake(r.GetTrackMediaItem(t, 0))
      if tk then
        local src = r.GetMediaItemTake_Source(tk)
        local path = src and r.GetMediaSourceFileName(src, "") or ""
        local fn = path:match("[^/\\]+$")
        if fn and fn ~= "" then newName = prettify(fn) end
        if (not newName or newName == "") then
          local ok, tn = r.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)
          if ok and tn ~= "" then newName = prettify(tn) end
        end
      end
    end
    if not newName or newName == "" then newName = prettify(tName(t)) end
    if newName ~= "" then
      if numberTracks then newName = string.format("%02d %s", num, newName) end
      r.GetSetMediaTrackInfo_String(t, "P_NAME", newName, true)
      renamed = renamed + 1
    end
    num = num + 1
  end
  if o.undo ~= false then r.Undo_EndBlock2(0, "Palette & Look: name from items", -1) end
  r.TrackList_AdjustWindows(false)
  if not o.silent then
    say(("Renamed %d track(s) in %s from their first item%s."):format(renamed, scopeWord(), numberTracks and (", numbered from " .. numberStart) or ""), "ok")
    rebuild()
  end
  return renamed
end
local function nameAndColor()
  local list = scopeList(); if not list then return end
  r.Undo_BeginBlock2(0)
  local renamed = nameFromItems({ list = list, undo = false, silent = true })
  local painted = applyRules({ list = list, undo = false, silent = true })
  r.Undo_EndBlock2(0, "Palette & Look: name and colour", -1)
  refreshUI()
  say(("Renamed %d and coloured %d track(s) in %s - one undo step."):format(renamed, painted, scopeWord()), "ok")
  rebuild()
end

local function stripEmoji(nm)
  for _, e in ipairs(ALL_EMOJI) do nm = nm:gsub(e .. " ?", "") end
  return (nm:gsub("^%s+", ""))
end
local function addEmoji()
  local list = scopeList(); if not list then return end
  r.Undo_BeginBlock2(0)
  local c = 0
  for _, t in ipairs(list) do
    local nm = tName(t)
    local _, why = decide(t, nm)
    local key = why
    if key and key:find("^rule:") then key = roleOf(nm) end
    if key and key:find("^group:") then key = "bus" end
    local e = key and ROLE_EMOJI[key]
    if e then r.GetSetMediaTrackInfo_String(t, "P_NAME", e .. " " .. stripEmoji(nm), true); c = c + 1 end
  end
  r.Undo_EndBlock2(0, "Palette & Look: add instrument emoji", -1)
  r.TrackList_AdjustWindows(false)
  if c == 0 then say("No track in " .. scopeWord() .. " has a family yet, so no emoji to add.", "warn")
  else say(("Added an instrument emoji to %d track name(s)."):format(c), "ok") end
  rebuild()
end
local function removeEmoji()
  local list = scopeList(); if not list then return end
  r.Undo_BeginBlock2(0)
  local c = 0
  for _, t in ipairs(list) do
    local nm = tName(t)
    local stripped = stripEmoji(nm)
    if stripped ~= nm then r.GetSetMediaTrackInfo_String(t, "P_NAME", stripped, true); c = c + 1 end
  end
  r.Undo_EndBlock2(0, "Palette & Look: remove emoji", -1)
  r.TrackList_AdjustWindows(false)
  say(c > 0 and ("Removed emoji from %d track name(s)."):format(c) or "No emoji found in " .. scopeWord() .. ".", c > 0 and "ok" or "info")
  rebuild()
end
-- whole project, like the other bus tools
local function upperBuses()
  r.Undo_BeginBlock2(0)
  local c = 0
  for i = 0, r.CountTracks(0) - 1 do
    local t = r.GetTrack(0, i)
    if isFolder(t) then
      local nm = tName(t)
      if nm ~= nm:upper() then r.GetSetMediaTrackInfo_String(t, "P_NAME", nm:upper(), true); c = c + 1 end
    end
  end
  r.Undo_EndBlock2(0, "Palette & Look: uppercase bus names", -1)
  r.TrackList_AdjustWindows(false)
  say(c > 0 and ("Uppercased %d bus name(s)."):format(c) or "Every bus name was already uppercase.", "ok")
  rebuild()
end

--------------------------------------------------------------------------------
-- rules editing helpers
--------------------------------------------------------------------------------
local function seedFromFamilies()
  MYRULES = {}
  for _, k in ipairs(ROLE_ORDER) do
    if k ~= "bus" and k ~= "return" then
      MYRULES[#MYRULES + 1] = { on = true, kind = "track", mode = "role", filter = FAMILY_LABEL[k], rgb = { RULES[k][1], RULES[k][2], RULES[k][3] } }
    end
  end
  MYRULES[#MYRULES + 1] = { on = true, kind = "track", mode = "special", filter = "(receive)", rgb = { RULES["return"][1], RULES["return"][2], RULES["return"][3] } }
  MYRULES[#MYRULES + 1] = { on = true, kind = "track", mode = "special", filter = "(folder)",  rgb = { RULES.bus[1], RULES.bus[2], RULES.bus[3] } }
  rulesSave(); rebuild()
  say(("Made %d rules from the family colours - one per family, plus FX returns and folders."):format(#MYRULES), "ok")
end

local function addRule()
  if newFilter == "" then say("Type the text to look for first.", "warn"); return end
  local mode = MODES[newModeIdx]
  if newFilter:sub(1, 1) == "(" then mode = "special" end
  table.insert(MYRULES, { on = true, kind = KINDS[newKindIdx], mode = mode, filter = newFilter, rgb = { newRGB[1], newRGB[2], newRGB[3] } })
  rulesSave(); rebuild()
  say(("Rule added: %s %s \"%s\"."):format(kindLabel(KINDS[newKindIdx]), modeLabel(mode), newFilter), "ok")
  newFilter = ""
end

--------------------------------------------------------------------------------
-- UI: tabs
--------------------------------------------------------------------------------
local function tabMyRules()
  ui.hint(ctx, "Top to bottom, first match wins. These beat the families.")
  if ui.button(ctx, "Import my SWS rules", { tip = "Read your SWS Auto Color rules (" .. SWSINI .. ") and use them here. Replaces this list - it asks first." }) then
    local list, err = scanSWS()
    if not list then say(err, "warn")
    elseif #MYRULES == 0 then
      local n = importSWS(list); rebuild()
      say(("Imported %d rule(s) from SWS Auto Color."):format(n), "ok")
    else pendingImport = list; ui.ask(ctx, "import") end
  end
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "Export to SWS", { tip = "Write this list into SWS Auto Color's file so SWS colours the same way. Backs the file up first - it asks before writing.", disabled = #MYRULES == 0 }) then
    ui.ask(ctx, "export")
  end
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "Seed from families", { tip = "Start a fresh list with one rule per family (Drums, Guitar, ...) in the family colours, plus FX returns and folders. Replaces this list." }) then
    if #MYRULES > 0 then ui.ask(ctx, "seed") else seedFromFamilies() end
  end
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "Clear all rules", { kind = "danger", tip = "Remove every rule from this list. Asks first.", disabled = #MYRULES == 0 }) then
    ui.ask(ctx, "clearRules")
  end

  -- add-rule row
  ui.vspace(ctx, 2)
  r.ImGui_AlignTextToFramePadding(ctx)
  ui.hint(ctx, "New rule for"); r.ImGui_SameLine(ctx)
  local ch, v = ui.combo(ctx, "##k", KIND_LABELS, newKindIdx, { w = 96, tip = "Track rules colour tracks. Marker and region rules colour markers and regions on the timeline (they match by name)." })
  if ch then newKindIdx = v end
  r.ImGui_SameLine(ctx, 0, 12)
  r.ImGui_AlignTextToFramePadding(ctx)
  ui.hint(ctx, "match"); r.ImGui_SameLine(ctx)
  ch, v = ui.combo(ctx, "##m", MODE_LABELS, newModeIdx, { w = 112, tip = MODE_TIP })
  if ch then newModeIdx = v end
  r.ImGui_SameLine(ctx, 0, 12)
  r.ImGui_SetNextItemWidth(ctx, 200)
  local fc, fv = r.ImGui_InputText(ctx, "##f", newFilter); if fc then newFilter = fv end
  ui.tip(ctx, "The text to look for in the name (or a track type like (folder)). Press Add rule when done.")
  r.ImGui_SameLine(ctx)
  local cc, cv = r.ImGui_ColorEdit3(ctx, "##nc", packRGB(newRGB), NOIN); if cc then newRGB = unpackRGB(cv) end
  ui.tip(ctx, "The colour this rule paints. Click to pick.")
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "Add rule", { tip = "Add this rule to the bottom of the list." }) then addRule() end

  -- the list
  ui.vspace(ctx, 2)
  if #MYRULES == 0 then
    ui.hint(ctx, "No rules yet. Add one above, seed from the families, or import your SWS rules.")
    ui.vspace(ctx, 6)
  else
    local cols = { { name = "On", w = 32 }, { name = "For", w = 70 }, { name = "Match", w = 118 }, { name = "Text" },
                   { name = "Colour", w = 56 }, { name = "Hits", w = 46 }, { name = "", w = 178 } }
    if ui.tableBegin(ctx, "rules", cols, { reserve = 96, minHeight = 120 }) then
      tableDrawn = true
      local del, mv = nil, nil
      for i, ru in ipairs(MYRULES) do
        r.ImGui_TableNextRow(ctx); r.ImGui_PushID(ctx, 1000 + i)
        r.ImGui_TableNextColumn(ctx)
        local oc, ov = r.ImGui_Checkbox(ctx, "##on", ru.on)
        if oc then ru.on = ov; rulesSave(); rebuild() end
        ui.tip(ctx, "Untick to keep the rule but stop it firing.")
        r.ImGui_TableNextColumn(ctx); r.ImGui_AlignTextToFramePadding(ctx); ui.hint(ctx, kindLabel(ru.kind))
        r.ImGui_TableNextColumn(ctx)
        local mc, mvi = ui.combo(ctx, "##mm", MODE_LABELS, modeIdx(ru.mode), { w = 110, tip = MODE_TIP })
        if mc then ru.mode = MODES[mvi]; rulesSave(); rebuild() end
        r.ImGui_TableNextColumn(ctx)
        r.ImGui_SetNextItemWidth(ctx, -1)
        local tc, tv = r.ImGui_InputText(ctx, "##ff", ru.filter)
        if tc then ru.filter = tv; markDirty() end
        ui.tip(ctx, "The text this rule looks for. Hits update a moment after you stop typing.")
        r.ImGui_TableNextColumn(ctx)
        local rc, rv = r.ImGui_ColorEdit3(ctx, "##rc", packRGB(ru.rgb), NOIN)
        if rc then ru.rgb = unpackRGB(rv); markDirty() end
        ui.tip(ctx, "The colour this rule paints. Click to pick.")
        r.ImGui_TableNextColumn(ctx)
        local hits = 0
        if ru.kind == "track" then
          local key = "rule:" .. i
          for _, row in ipairs(rows) do if row.kind == key then hits = hits + 1 end end
        end
        r.ImGui_AlignTextToFramePadding(ctx)
        ui.text(ctx, tostring(hits), hits > 0 and ui.accents.teal or T.muted)
        ui.tip(ctx, ru.kind == "track" and "How many tracks this rule would colour right now." or "Marker and region rules are counted when you colour them.")
        r.ImGui_TableNextColumn(ctx)
        if ui.button(ctx, "Up", { small = true, tip = "Move this rule up - earlier rules win.", disabled = i == 1 }) then mv = { i, -1 } end
        r.ImGui_SameLine(ctx)
        if ui.button(ctx, "Down", { small = true, tip = "Move this rule down.", disabled = i == #MYRULES }) then mv = { i, 1 } end
        r.ImGui_SameLine(ctx)
        if ui.button(ctx, "Remove", { small = true, kind = "ghost", tip = "Remove this one rule." }) then del = i end
        r.ImGui_PopID(ctx)
      end
      r.ImGui_EndTable(ctx)
      if del then
        local gone = MYRULES[del]
        table.remove(MYRULES, del); rulesSave(); rebuild()
        say(("Removed the rule \"%s\"."):format(gone and gone.filter or "?"), "ok")
      end
      if mv then
        local i, d = mv[1], mv[2]
        if MYRULES[i + d] then MYRULES[i], MYRULES[i + d] = MYRULES[i + d], MYRULES[i]; rulesSave(); rebuild() end
      end
    end
  end
  if ui.button(ctx, "Colour markers and regions now", { tip = "Apply the marker and region rules above to the timeline. One undo step." }) then applyMarkers() end
end

local function tabFamilies()
  ui.hint(ctx, "The fallback when no rule matches. Synonym-aware: 'Gtr Dist L', 'OD Rhythm' and 'Les Paul' all read as Guitar.")
  ui.vspace(ctx, 2)
  local changed = false
  for i, k in ipairs(ROLE_ORDER) do
    local c = RULES[k]
    local rc, rv = r.ImGui_ColorEdit3(ctx, FAMILY_LABEL[k] .. "##fam_" .. k, packRGB(c), NOIN)
    if rc then RULES[k] = unpackRGB(rv); changed = true end
    ui.tip(ctx, "Colour for the " .. FAMILY_LABEL[k] .. " family. Click to pick.")
    if i % 4 ~= 0 and i < #ROLE_ORDER then r.ImGui_SameLine(ctx, 0, 24) end
  end
  if changed then markDirty() end
  ui.vspace(ctx, 4)
  if ui.button(ctx, "Reset to my SWS colours", { tip = "Put every family back to the colours from your SWS Auto Color setup." }) then
    for k, v in pairs(DEFAULTS) do RULES[k] = { v[1], v[2], v[3] } end
    saveRules(); rebuild(); say("Family colours reset to your SWS colours.", "ok")
  end
  r.ImGui_SameLine(ctx, 0, 18)
  local xc, xv = ui.toggle(ctx, "Tracks of one family inside a folder step lighter", shadeChildren,
    "Inside a folder, the second, third... track of the same family gets a slightly lighter shade, so a drum kit reads as one colour with depth.")
  if xc then shadeChildren = xv end
end

local function tabPalettes()
  ui.hint(ctx, "Pick a palette, then choose how to spread it over " .. scopeWord() .. ".")
  ui.vspace(ctx, 2)
  for i, P in ipairs(PALETTES) do
    local sel = (i == paletteIdx)
    if ui.button(ctx, P.name .. "##p" .. i, { kind = sel and "primary" or "secondary", small = true, w = 110,
        tip = sel and "The active palette." or ("Use the " .. P.name .. " palette.") }) then
      paletteIdx = i
      say("Palette: " .. P.name .. ".", "info")
    end
    r.ImGui_SameLine(ctx, 0, 10)
    for j = 1, #P.cols do
      ui.swatch(ctx, "##s" .. i .. "_" .. j, u32(P.cols[j]), { w = 12, h = 12 })
      if j < #P.cols then r.ImGui_SameLine(ctx, 0, 2) end
    end
  end
  ui.vspace(ctx, 6)
  if ui.button(ctx, "Colour by family", { tip = "Each instrument family in " .. scopeWord() .. " gets the next colour of the palette (drums one colour, guitars another...)." }) then applyByRole() end
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "Colour by folder", { tip = "Every folder gets its own palette colour and the tracks inside it lighter shades. Always the whole project (it follows the folder tree)." }) then applyByFolder() end
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "Palette in order", { tip = "Walk the palette down " .. scopeWord() .. " in track order, repeating when it runs out." }) then applyPaletteInOrder() end
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "Surprise (re-roll)", { tip = "Random colours across " .. scopeWord() .. "; tracks with the same name share one. Asks first when it is the whole project." }) then
    if scope == "all" then ui.ask(ctx, "surprise") else applySurprise() end
  end
end

local function tabTools()
  ui.section(ctx, "Gradient")
  ui.hint(ctx, "A smooth run from one colour to another across " .. scopeWord() .. ", in track order.")
  local ac, av = r.ImGui_ColorEdit3(ctx, "from##ga", packRGB(gradA), NOIN); if ac then gradA = unpackRGB(av) end
  ui.tip(ctx, "First colour. Click to pick.")
  r.ImGui_SameLine(ctx, 0, 14)
  local bc, bv = r.ImGui_ColorEdit3(ctx, "to##gb", packRGB(gradB), NOIN); if bc then gradB = unpackRGB(bv) end
  ui.tip(ctx, "Last colour. Click to pick.")
  r.ImGui_SameLine(ctx, 0, 14)
  if ui.button(ctx, "Apply gradient", { tip = "Colour " .. scopeWord() .. " from the first colour to the last." }) then applyGradient() end
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "Swap", { kind = "ghost", tip = "Swap the two colours." }) then gradA, gradB = gradB, gradA end

  ui.section(ctx, "Nudge what is already there")
  if ui.button(ctx, "Lighter", { tip = "Every coloured track in " .. scopeWord() .. " a step lighter." }) then nudge("light", 0.07) end
  r.ImGui_SameLine(ctx); if ui.button(ctx, "Darker", { tip = "A step darker." }) then nudge("light", -0.07) end
  r.ImGui_SameLine(ctx); if ui.button(ctx, "More colour", { tip = "Stronger, more saturated." }) then nudge("sat", 0.10) end
  r.ImGui_SameLine(ctx); if ui.button(ctx, "Less colour", { tip = "Softer, closer to grey." }) then nudge("sat", -0.10) end
  r.ImGui_SameLine(ctx); if ui.button(ctx, "Hue +", { tip = "Turn every colour a little round the colour wheel." }) then nudge("hue", 0.04) end
  r.ImGui_SameLine(ctx); if ui.button(ctx, "Hue -", { tip = "Turn the other way round the colour wheel." }) then nudge("hue", -0.04) end

  ui.section(ctx, "Structure and housekeeping")
  if ui.button(ctx, "Match to first selected", { tip = "Give every other track in " .. scopeWord() .. " the colour of the first one." }) then copyFirstColor() end
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "Children inherit folder", { tip = "Tracks inside a folder take a lighter shade of the folder's colour. Always the whole project." }) then inheritFromParent() end
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "Clear colours", { kind = "danger", tip = "Remove the colour from " .. scopeWord() .. " (back to REAPER's default). Asks first when it is the whole project. Undo brings them back." }) then
    if scope == "all" then ui.ask(ctx, "clearColours") else clearColors() end
  end

  ui.section(ctx, "Names")
  if ui.button(ctx, "Add instrument emoji", { tip = "Put a small instrument picture at the front of each track name in " .. scopeWord() .. " (drums, guitar, keys...). REAPER shows them; this window cannot." }) then addEmoji() end
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "Remove emoji", { tip = "Take those pictures back out of the names in " .. scopeWord() .. "." }) then removeEmoji() end
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "UPPERCASE buses", { tip = "Every folder/bus name to UPPERCASE so they read as sections. Whole project." }) then upperBuses() end
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "Refresh", { kind = "ghost", tip = "Re-read the project and rules now (it also happens by itself)." }) then rebuild(); say("Refreshed: " .. #rows .. " track(s).", "info") end
end

local function tabTracks()
  ui.hint(ctx, "Now = the colour a track has.  Want = what the rules and families would give it.  Click a Want swatch to colour just that track.")
  local cols = { { name = "#", w = 34 }, { name = "Now", w = 40 }, { name = "Want", w = 44 }, { name = "Track" }, { name = "Why", w = 170 } }
  if ui.tableBegin(ctx, "tracks", cols, { reserve = 62, minHeight = 120 }) then
    tableDrawn = true
    local map = safe.guidMap(0)          -- resolved once per frame, discarded after
    for i, row in ipairs(rows) do
      local live = rowTrack(row, map)
      r.ImGui_TableNextRow(ctx); r.ImGui_PushID(ctx, i)
      r.ImGui_TableNextColumn(ctx); r.ImGui_AlignTextToFramePadding(ctx); ui.dim(ctx, tostring(i))
      r.ImGui_TableNextColumn(ctx)
      if live then
        local c = getRGB(live)
        ui.swatch(ctx, "##c", c and u32(c) or nil, { w = 22, h = 16, tip = c and ("Now " .. hexOf(c)) or "No colour yet." })
      else ui.text(ctx, "x", T.danger) end
      r.ImGui_TableNextColumn(ctx)
      if row.want and live then
        if ui.swatch(ctx, "##w", u32(row.want), { w = 22, h = 16, tip = "Click to give just this track " .. hexOf(row.want) .. "." }) then
          r.Undo_BeginBlock2(0); setCol(live, row.want); r.Undo_EndBlock2(0, "Palette & Look: colour one track", -1)
          refreshUI(); say(("Coloured %s %s."):format(row.name, hexOf(row.want)), "ok"); rebuild()
        end
      else r.ImGui_AlignTextToFramePadding(ctx); ui.dim(ctx, "-") end
      r.ImGui_TableNextColumn(ctx)
      r.ImGui_AlignTextToFramePadding(ctx)
      if not live then ui.text(ctx, row.name .. "   (deleted)", T.danger)
      elseif row.kind == "bus" or (row.kind and row.kind:find("^group:")) then ui.text(ctx, row.name, ui.accents.teal)
      else ui.text(ctx, row.name) end
      r.ImGui_TableNextColumn(ctx)
      r.ImGui_AlignTextToFramePadding(ctx)
      local col = T.muted
      if row.kind then col = row.kind:find("^rule:") and ui.accents.teal or T.text end
      ui.text(ctx, row.label or "-", col)
      r.ImGui_PopID(ctx)
    end
    r.ImGui_EndTable(ctx)
  end
end

--------------------------------------------------------------------------------
-- UI: frame
--------------------------------------------------------------------------------
local SCOPES = {
  { id = "sel", label = "Selection",     tip = "Only the tracks selected in REAPER right now." },
  { id = "all", label = "Whole project", tip = "Every track in the project." },
}

local function frame()
  tableDrawn = false
  ui.header(ctx, APP, "colour and name your tracks from what they are", function()
    local lc, lv = ui.toggle(ctx, "LIVE", liveOn,
      "Watch the project and re-colour " .. scopeWord() .. " by itself whenever tracks are added, renamed, armed or muted. " ..
      "Turning it on colours once right away. Bursts of changes are grouped (about twice a second at most).")
    if lc then
      liveOn = lv; liveSig = ""
      say(liveOn and ("Live colouring ON for " .. scopeWord() .. " - new and renamed tracks colour themselves.") or "Live colouring off.", liveOn and "ok" or "info")
    end
    r.ImGui_SameLine(ctx, 0, 10)
    ui.dockToggle(ctx)
  end, 150)

  if #rows == 0 then
    ui.empty(ctx, "No tracks in this project", "Add tracks or open a session, then come back to colour and name them.")
    if ui.pushToBottom then ui.pushToBottom(ctx, 44) end
    ui.status(ctx, { idle = "Waiting for tracks." })
    return
  end

  -- scope + options
  ui.section(ctx, "Apply to")
  local newScope = ui.segmented(ctx, "scope", SCOPES, scope)
  if newScope ~= scope then scope = newScope; liveSig = "" end
  r.ImGui_SameLine(ctx, 0, 18)
  local mc, mv = ui.toggle(ctx, "markers and regions too", doMarkers,
    "When applying colours, also colour markers and regions from the marker/region rules.")
  if mc then doMarkers = mv end
  r.ImGui_SameLine(ctx, 0, 18)
  local uc, uv = ui.toggle(ctx, "my rules first", useMyRules,
    "Check your rules before the families. Untick to colour from families and structure only.")
  if uc then useMyRules = uv; rebuild() end

  -- primary row
  ui.vspace(ctx, 4)
  if ui.button(ctx, "APPLY COLOURS", { kind = "primary", w = 200, h = 34,
      tip = "Colour " .. scopeWord() .. ": your rules first, then instrument families, then folders/buses/FX returns. One undo step." }) then
    applyRules()
  end
  r.ImGui_SameLine(ctx, 0, 14)
  if ui.button(ctx, "Name from items", { h = 34, tip = "Rename each track in " .. scopeWord() .. " after the file on its first item (numbers and extensions tidied away)." }) then nameFromItems() end
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "Name + colour", { h = 34, tip = "Name from items, then apply colours - one undo step." }) then nameAndColor() end
  r.ImGui_SameLine(ctx, 0, 14)
  local nc, nv = ui.toggle(ctx, "Number them", numberTracks, "When naming, put a number in front of each name (01 Kick, 02 Snare...).")
  if nc then numberTracks = nv end
  r.ImGui_SameLine(ctx, 0, 6)
  r.ImGui_AlignTextToFramePadding(ctx); ui.hint(ctx, "from"); r.ImGui_SameLine(ctx, 0, 6)
  r.ImGui_SetNextItemWidth(ctx, 56)
  local sc, sv = r.ImGui_InputInt(ctx, "##start", numberStart, 0, 0)
  if sc then numberStart = math.max(1, sv) end
  ui.tip(ctx, "The first number to use.")

  -- tabs
  ui.vspace(ctx, 4)
  if r.ImGui_BeginTabBar(ctx, "tabs") then
    if r.ImGui_BeginTabItem(ctx, "My rules") then ui.vspace(ctx, 2); tabMyRules();  r.ImGui_EndTabItem(ctx) end
    if r.ImGui_BeginTabItem(ctx, "Families") then ui.vspace(ctx, 2); tabFamilies(); r.ImGui_EndTabItem(ctx) end
    if r.ImGui_BeginTabItem(ctx, "Palettes") then ui.vspace(ctx, 2); tabPalettes(); r.ImGui_EndTabItem(ctx) end
    if r.ImGui_BeginTabItem(ctx, "Tools")    then ui.vspace(ctx, 2); tabTools();    r.ImGui_EndTabItem(ctx) end
    if r.ImGui_BeginTabItem(ctx, "Tracks")   then ui.vspace(ctx, 2); tabTracks();   r.ImGui_EndTabItem(ctx) end
    r.ImGui_EndTabBar(ctx)
  end

  -- confirms (drawn every frame, at the window root so any tab can open them)
  if ui.confirm(ctx, "clearRules", {
      title = "Clear all your rules?",
      text  = ("Every one of the %d rule(s) in the list goes away. Family colours stay. REAPER's undo cannot bring rules back."):format(#MYRULES),
      ok = "Clear rules", danger = true }) then
    MYRULES = {}; rulesSave(); rebuild(); say("Cleared all rules.", "ok")
  end
  if ui.confirm(ctx, "seed", {
      title = "Replace your rules with the family seed?",
      text  = ("The %d rule(s) you have now are replaced by one rule per family plus FX returns and folders. This cannot be undone."):format(#MYRULES),
      ok = "Replace", danger = true }) then
    seedFromFamilies()
  end
  if ui.confirm(ctx, "import", {
      title = "Replace your rules with the SWS ones?",
      text  = ("SWS Auto Color has %d rule(s). They replace the %d rule(s) in this list, and the old list is not kept anywhere. Your family colours stay."):format(pendingImport and #pendingImport or 0, #MYRULES),
      ok = "Import", danger = #MYRULES > 0 }) then
    if pendingImport then
      local n = importSWS(pendingImport); pendingImport = nil; rebuild()
      say(("Imported %d rule(s) from SWS Auto Color."):format(n), "ok")
    end
  end
  if ui.confirm(ctx, "export", {
      title = "Write your rules into SWS Auto Color?",
      text  = ("Your %d rule(s) replace the Auto Color rules in SWS's settings file (%s), and Auto Color is switched on. Every other line in that file - icons, layouts, other switches - is kept, and a backup copy is saved beside it first. SWS keeps its own copy in memory while REAPER runs, so restart REAPER and check its Auto Color window."):format(#MYRULES, SWSINI),
      ok = "Write to SWS" }) then
    local n, bak = exportSWS()
    if n then say(("Wrote %d rule(s) into SWS Auto Color. Backup: %s. Restart REAPER to see them in SWS."):format(n, tostring(bak)), "ok")
    else say("Could not write to SWS: " .. tostring(bak), "danger") end
  end
  if ui.confirm(ctx, "clearColours", {
      title = "Clear the colour on every track?",
      text  = ("All %d track(s) in the project go back to REAPER's default colour. One undo step brings them back."):format(#rows),
      ok = "Clear colours", danger = true }) then
    clearColors()
  end
  if ui.confirm(ctx, "surprise", {
      title = "Random colours on the whole project?",
      text  = ("All %d track(s) get random colours (tracks with the same name share one). One undo step brings the old colours back."):format(#rows),
      ok = "Surprise me" }) then
    applySurprise()
  end

  -- short tabs (Families / Palettes / Tools) pin the footer to the bottom;
  -- the table tabs already sized themselves to leave room for it
  if ui.pushToBottom and not tableDrawn then ui.pushToBottom(ctx, 44) end
  ui.status(ctx, { idle = "Choose Selection or Whole project, then press Apply colours." })
end

--------------------------------------------------------------------------------
-- loop
--------------------------------------------------------------------------------
rebuild()
local function loop()
  local now = r.time_precise()

  -- rules / family colours typed a moment ago: save + re-scan once, not per key
  if dirtyT and now - dirtyT > 0.4 then
    dirtyT = nil
    rulesSave(); saveRules(); rebuild()
  end

  -- WATCHDOG.  If a track was added, deleted, renamed, reordered, armed or
  -- muted, resync the list so the table never renders stale data.  Throttled
  -- to ~4Hz because the signature walks every track; that has to stay cheap
  -- on a 452-track session.  LIVE rides the same signature, coalesced so a
  -- burst of changes becomes one apply (and one undo step) per half second.
  if now - lastSigT > 0.25 then
    lastSigT = now
    local sig = fullSig()
    if sig ~= lastSig then lastSig = sig; rebuild() end
    if liveOn and sig ~= liveSig and now - liveApplyT >= 0.5 then
      liveSig = sig; liveApplyT = now
      applyRules({ silent = true, quiet = true })
    end
  end

  local open = ui.window(ctx, { title = APP, accent = ui.accents.teal, w = 920, h = 700, minW = 720, minH = 480 }, frame)
  if open then r.defer(loop)
  elseif dirtyT then rulesSave(); saveRules() end   -- closed mid-edit: do not lose the typing
end
r.defer(loop)
