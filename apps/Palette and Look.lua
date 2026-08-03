-- @description NPH Palette & Look
-- @version 1.0.0
-- @author Jason Zac
-- @link https://daw.nathanielschool.com
-- @donation https://daw.nathanielschool.com/donate
-- @about Colour and name tracks from meaning, with rules, palettes and a live watcher.
-- @changelog
--   1.0.0 - first public release. Crash-hardened (GUID identity + ValidatePtr2),
--           signature-based change detection, shared safety library.

--[[
  Palette & Look  (v3)  -  REAPER / ReaImGui
  ------------------------------------------------------------------------------
  App #3 in the NathanielSchool suite.  The master COLOR / LOOK / NAMING tool.
  Goal: the single best place to do colour work in REAPER.

  Three layers, evaluated in this order:

    1. MY RULES   an ordered filter->colour table, exactly like SWS Auto Color
                  but with real match modes (contains / word / starts / exact /
                  pattern / role), live auto-apply, and one-click import of your
                  existing sws-autocoloricon.ini so nothing is lost.
    2. FAMILIES   synonym-aware fallback.  "Gtr Dist L", "OD Rhythm" and
                  "Les Paul" all resolve to guitar without you writing a rule.
    3. STRUCTURE  folders, buses and true FX returns (detected from receives +
                  the plugins on the chain, not just the name).

  Plus: markers & regions coloured by the same rule table, rename-from-item,
  numbering, emoji, palettes, gradients, shade/saturate tools.
  One undo per action.  Dockable.  Requires ReaImGui.
--]]

local r = reaper

-- ReaImGui renames enum constants between releases, and a renamed constant is
-- a nil-call crash the moment the window opens - not a graceful degradation.
-- nph_imgui bridges the old and new spellings in one place. See that file for
-- the two renames measured on ReaImGui/Dear ImGui 1.92.1.
do
  local sep = package.config:sub(1, 1)
  local here = ({reaper.get_action_context()})[2]:match("(.*" .. sep .. ")") or ""
  package.path = here .. "lib" .. sep .. "?.lua;" ..
                 here .. ".." .. sep .. "NPH" .. sep .. "lib" .. sep .. "?.lua;" ..
                 reaper.GetResourcePath() .. "/Scripts/NPH REAPER Suite/NPH/lib/?.lua;" ..
                 package.path
  local ok, compat = pcall(require, "nph_imgui")
  if ok then compat.install() end
end
if not r.ImGui_CreateContext then
  r.ShowMessageBox("Needs ReaImGui (Extensions > ReaPack > Browse > 'ReaImGui', install, restart).","Palette & Look",0); return
end
math.randomseed(os.time())

local EXT   = "NSM_PaletteLook"
local SEP   = package.config:sub(1,1)
local SWSINI= r.GetResourcePath()..SEP.."sws-autocoloricon.ini"

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
-- roles / synonyms (shared brain across the suite)
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
local ROLE_EMOJI  = { guitar="🎸", acoustic="🪕", bass="🎸", drums="🥁", vocal="🎤", harm="🎙️", keys="🎹",
                      synth="🎛️", strings="🎻", brass="🎺", wind="🎶", ["return"]="💧", bus="📁" }
local ALL_EMOJI = { "🎸","🪕","🥁","🎤","🎙️","🎹","🎛️","🎻","🎺","🎶","🎚️","💧","🟨","📁" }

local FX_WORDS = {"verb","reverb","rvb","delay","dly","echo","slap","plate","hall",
                  "chamber","spring","space","fx","send","return","rtn","ambience","ambient"}
local FX_PLUGINS = {"valhalla","reverb","verb","delay","echo","lexicon","emt","plate","raum",
                    "blackhole","shimmer","convolution","spaces","cinematic rooms","pro-r","h-delay","h-reverb"}

local ROLE_ORDER = { "guitar","acoustic","bass","drums","vocal","harm","keys","synth","strings","brass","wind","return","bus" }

--------------------------------------------------------------------------------
-- FAMILY colours.  Defaults are YOUR real colours, read out of your own
-- sws-autocoloricon.ini, so this app starts where your muscle memory already is.
--------------------------------------------------------------------------------
local DEFAULTS = {
  guitar   = {243, 79,255},   -- 0xF34FFF  your SWS "Guitar"
  bass     = {182, 48, 50},   -- 0xB63032  your SWS "Bass"
  harm     = {105, 36,160},   -- 0x6924A0  your SWS "Harm"
  ["return"] = {255,241, 76}, -- 0xFFF14C  your SWS "(receive)" - sends come back yellow
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
for k,v in pairs(DEFAULTS) do RULES[k] = {v[1],v[2],v[3]} end

local function saveRules()
  for k,c in pairs(RULES) do
    r.SetExtState(EXT, "rule_"..k, string.format("%d,%d,%d", c[1], c[2], c[3]), true)
  end
end
local function loadRules()
  for k,_ in pairs(RULES) do
    local s = r.GetExtState(EXT, "rule_"..k)
    if s and s ~= "" then
      local a,b,c = s:match("(%d+),(%d+),(%d+)")
      if a then RULES[k] = { tonumber(a), tonumber(b), tonumber(c) } end
    end
  end
end
loadRules()

--------------------------------------------------------------------------------
-- MY RULES : the SWS-style ordered filter table, but smarter
--   { on, kind="track"|"marker"|"region", mode, filter, rgb={r,g,b} }
--------------------------------------------------------------------------------
local MODES = { "contains", "word", "starts", "exact", "pattern", "role" }
local MYRULES = {}

local function rulesSerialize()
  local out = {}
  for _,ru in ipairs(MYRULES) do
    out[#out+1] = table.concat({ ru.on and 1 or 0, ru.kind, ru.mode,
      (ru.filter:gsub("|","/")), string.format("%02X%02X%02X", ru.rgb[1],ru.rgb[2],ru.rgb[3]) }, "|")
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
    local on,kind,mode,filter,hex = line:match("^(%d)|([^|]*)|([^|]*)|([^|]*)|(%x%x%x%x%x%x)$")
    if on then
      MYRULES[#MYRULES+1] = { on = on=="1", kind=kind, mode=mode, filter=filter,
        rgb = { tonumber(hex:sub(1,2),16), tonumber(hex:sub(3,4),16), tonumber(hex:sub(5,6),16) } }
    end
  end
end
rulesLoad()

--------------------------------------------------------------------------------
-- SWS ini import / export
--------------------------------------------------------------------------------
local function readFile(p) local f=io.open(p,"rb"); if not f then return nil end local c=f:read("*a"); f:close(); return c end

local function importSWS()
  local txt = readFile(SWSINI)
  if not txt then return nil, "No sws-autocoloricon.ini found at "..SWSINI end
  local found = 0
  local imported = {}
  for line in txt:gmatch("[^\r\n]+") do
    local body = line:match("^AutoColor%s*%d+%s*=%s*(.+)$")
    if body then
      -- <type> <filter possibly quoted or bare> <colorint> "" "" ""
      local typ, rest = body:match("^(%d+)%s+(.*)$")
      if typ then
        local filter, col
        if rest:sub(1,1) == '"' then
          filter, col = rest:match('^"([^"]*)"%s+(%-?%d+)')
        else
          filter, col = rest:match("^(%S+)%s+(%-?%d+)")
        end
        if filter and col then
          col = tonumber(col)
          local rgb = { (col>>16)&0xFF, (col>>8)&0xFF, col&0xFF }
          local kind = (typ=="1") and "marker" or (typ=="2") and "region" or "track"
          -- short filters (V / C / B) are almost always whole-name labels, not substrings
          -- SWS itself does a case-insensitive substring match (with * wildcards),
          -- so import as "contains" to reproduce your existing behaviour exactly.
          local mode = "contains"
          if filter:sub(1,1) == "(" then mode = "special" end
          imported[#imported+1] = { on=true, kind=kind, mode=mode, filter=filter, rgb=rgb }
          found = found + 1
        end
      end
    end
  end
  if found == 0 then return nil, "Found the ini but no AutoColor lines in it." end
  MYRULES = imported
  rulesSave()
  return found
end

local function exportSWS()
  local bak = SWSINI..".paletteBackup"
  local cur = readFile(SWSINI)
  if cur then local f=io.open(bak,"wb"); if f then f:write(cur); f:close() end end
  local lines = { "[SWS]" }
  local n = 0
  for _,ru in ipairs(MYRULES) do
    n = n + 1
    local typ = (ru.kind=="marker") and 1 or (ru.kind=="region") and 2 or 0
    local col = 0x02000000 | (ru.rgb[1]<<16) | (ru.rgb[2]<<8) | ru.rgb[3]
    lines[#lines+1] = string.format('AutoColor %d=%d %s %d "" "" ""', n, typ, ru.filter, col)
  end
  lines[#lines+1] = "AutoColorCount="..n
  lines[#lines+1] = "AutoColorEnable=1"
  lines[#lines+1] = "AutoColorMarkerEnable=1"
  lines[#lines+1] = "AutoColorRegionEnable=1"
  lines[#lines+1] = "AutoIconEnable=0"
  lines[#lines+1] = "AutoLayoutEnable=0"
  local f = io.open(SWSINI, "wb")
  if not f then return nil, "Could not write "..SWSINI end
  f:write(table.concat(lines,"\n").."\n"); f:close()
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
local function isFolder(t) return r.GetMediaTrackInfo_Value(t,"I_FOLDERDEPTH") == 1 end
local function nameSaysFX(name)
  local low = " "..name:lower().." "
  for _,w in ipairs(FX_WORDS) do
    if low:find("%f[%w]"..w:gsub("%-","%%-").."%f[%W]") then return true end
  end
  return false
end
local function fxChainSaysFX(t)
  for i=0, r.TrackFX_GetCount(t)-1 do
    local ok, nm = r.TrackFX_GetFXName(t, i, "")
    if ok and nm then
      local low = nm:lower()
      for _,w in ipairs(FX_PLUGINS) do if low:find(w,1,true) then return true end end
    end
  end
  return false
end
local function tName(t)
  local ok,nm = r.GetSetMediaTrackInfo_String(t,"P_NAME","",false)
  if ok and nm~="" then return nm end
  return "Track "..math.floor(r.GetMediaTrackInfo_Value(t,"IP_TRACKNUMBER"))
end
local function isReturn(t)
  local recv = r.GetTrackNumSends(t, -1)
  local nm = select(2, r.GetSetMediaTrackInfo_String(t,"P_NAME","",false)) or ""
  if recv and recv > 0 then
    if nameSaysFX(nm) or fxChainSaysFX(t) then return true end
  end
  if nameSaysFX(nm) and fxChainSaysFX(t) then return true end
  return false
end

-- SWS-style wildcard -> lua pattern
local function wildToPattern(f)
  local p = f:gsub("([%^%$%(%)%%%.%[%]%+%-%?])","%%%1"):gsub("%*",".*")
  return "^"..p.."$"
end

local function ruleMatchesName(ru, name)
  local low, f = name:lower(), ru.filter:lower()
  if f == "" then return false end
  if ru.mode == "contains" then
    if f:find("%*") then return low:find(wildToPattern(f)) ~= nil end
    return low:find(f, 1, true) ~= nil
  elseif ru.mode == "word" then
    for w in low:gmatch("[%w']+") do if w == f then return true end end
    return false
  elseif ru.mode == "starts" then
    return low:sub(1,#f) == f
  elseif ru.mode == "exact" then
    return low == f
  elseif ru.mode == "pattern" then
    local ok, res = pcall(string.find, low, ru.filter)
    return ok and res ~= nil
  elseif ru.mode == "role" then
    return roleOf(name) == f
  end
  return false
end

local function ruleMatchesTrack(ru, t, name)
  if ru.mode == "special" or ru.filter:sub(1,1) == "(" then
    local s = ru.filter:lower()
    if s == "(folder)"  then return isFolder(t) end
    if s == "(receive)" then local n=r.GetTrackNumSends(t,-1); return n and n>0 end
    if s == "(send)"    then local n=r.GetTrackNumSends(t,0);  return n and n>0 end
    if s == "(master)"  then return t == r.GetMasterTrack(0) end
    if s == "(unnamed)" then local ok,nm=r.GetSetMediaTrackInfo_String(t,"P_NAME","",false); return not ok or nm=="" end
    if s == "(any)"     then return true end
    if s == "(armed)"   then return r.GetMediaTrackInfo_Value(t,"I_RECARM")==1 end
    if s == "(muted)"   then return r.GetMediaTrackInfo_Value(t,"B_MUTE")==1 end
    if s == "(empty)"   then return r.CountTrackMediaItems(t)==0 end
    if s == "(midi)"    then
      for i=0,r.CountTrackMediaItems(t)-1 do
        local tk = r.GetActiveTake(r.GetTrackMediaItem(t,i))
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
local function clamp(v) return math.max(0, math.min(255, math.floor(v+0.5))) end
local function setCol(t, rgb) r.SetTrackColor(t, r.ColorToNative(clamp(rgb[1]), clamp(rgb[2]), clamp(rgb[3]))) end
local function u32(rgb) return (clamp(rgb[1])<<24)|(clamp(rgb[2])<<16)|(clamp(rgb[3])<<8)|0xff end
local function getRGB(t)
  local c = r.GetTrackColor(t); if c == 0 then return nil end
  local a,b,d = r.ColorFromNative(c); return {a,b,d}
end
local function trackU32(t) local c=getRGB(t); return c and u32(c) or 0x3A3A44ff end
local function shade(rgb, f)
  local function m(c) if f >= 0 then return c + (255-c)*f else return c*(1+f) end end
  return { m(rgb[1]), m(rgb[2]), m(rgb[3]) }
end
local function randRGB() return { math.random(60,255), math.random(60,255), math.random(60,255) } end
local function rgb2hsl(c)
  local R,G,B = c[1]/255, c[2]/255, c[3]/255
  local mx, mn = math.max(R,G,B), math.min(R,G,B)
  local h,s,l = 0,0,(mx+mn)/2
  if mx ~= mn then
    local d = mx-mn
    s = l > 0.5 and d/(2-mx-mn) or d/(mx+mn)
    if mx==R then h=(G-B)/d + (G<B and 6 or 0) elseif mx==G then h=(B-R)/d+2 else h=(R-G)/d+4 end
    h = h/6
  end
  return h,s,l
end
local function hsl2rgb(h,s,l)
  local function hue(p,q,t)
    if t<0 then t=t+1 end; if t>1 then t=t-1 end
    if t<1/6 then return p+(q-p)*6*t end
    if t<1/2 then return q end
    if t<2/3 then return p+(q-p)*(2/3-t)*6 end
    return p
  end
  if s==0 then return {l*255,l*255,l*255} end
  local q = l<0.5 and l*(1+s) or l+s-l*s
  local p = 2*l-q
  return { hue(p,q,h+1/3)*255, hue(p,q,h)*255, hue(p,q,h-1/3)*255 }
end
local function lerp(a,b,f) return { a[1]+(b[1]-a[1])*f, a[2]+(b[2]-a[2])*f, a[3]+(b[3]-a[3])*f } end
local function hexOf(c) return string.format("#%02X%02X%02X", clamp(c[1]),clamp(c[2]),clamp(c[3])) end
local function packRGB(c) return (clamp(c[1])<<16)|(clamp(c[2])<<8)|clamp(c[3]) end
local function unpackRGB(v) return { (v>>16)&0xFF, (v>>8)&0xFF, v&0xFF } end
local function baseKey(name)
  local s = name:lower():gsub("[^%a]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  return (s:gsub("%s+[lr]$", ""))
end

--------------------------------------------------------------------------------
-- state
--------------------------------------------------------------------------------
local ctx = r.ImGui_CreateContext('Palette & Look')
local paletteIdx  = 10
local scope       = "sel"
local rows, logLines = {}, {}
-- Resync trigger. NOT GetProjectStateChangeCount - measured in REAPER 7.77, that
-- counter does NOT move when a track is inserted, renamed or deleted (it sat on 8
-- through all three), so any watchdog built on it never fires. We compare a cheap
-- signature of the track list instead. See the watchdog in loop().
local lastSig, lastSigT = nil, 0
local firstFrame, dockPending = true, nil
local shadeChildren = true
local numberTracks, numberStart = false, 1
local useMyRules   = true
local doMarkers    = true
local liveOn       = false
local liveSig, liveT = "", 0
local gradA, gradB = {243,79,255}, {90,200,255}
local newFilter, newModeIdx, newKindIdx = "", 1, 1
local newRGB = {200,120,255}
local statusMsg = ""
local function log(s) logLines[#logLines+1]=s; if #logLines>200 then table.remove(logLines,1) end; statusMsg=s end

local function scopeTracks()
  local t = {}
  if scope=="sel" then
    for i=0,r.CountSelectedTracks(0)-1 do t[#t+1]=r.GetSelectedTrack(0,i) end
    if #t==0 then for i=0,r.CountTracks(0)-1 do t[#t+1]=r.GetTrack(0,i) end end
  else
    for i=0,r.CountTracks(0)-1 do t[#t+1]=r.GetTrack(0,i) end
  end
  return t
end

-- the whole decision, in one place
local function decide(t, name)
  if useMyRules then
    for _,ru in ipairs(MYRULES) do
      if ru.on and ru.kind == "track" and ruleMatchesTrack(ru, t, name) then
        return ru.rgb, "rule:"..ru.filter
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
  if group and role and RULES[role] then return shade(RULES[role], -0.32), "group" end
  if group then return RULES.bus, "bus" end
  if role and RULES[role] then return RULES[role], role end
  return nil, nil
end

local function classify(t)
  local nm = tName(t)
  local _, why = decide(t, nm)
  return why, nm
end

-- CRASH FIX (v2).  This table used to hold `track = <MediaTrack*>`, and the
-- UI read it again on every defer frame.  REAPER frees that pointer the instant
-- the track is deleted, so deleting a track with this window open handed a
-- dangling pointer straight to trackU32() / setCol() and killed REAPER inside
-- its own C++, where the pcall around frame() cannot reach.  That was Jason's
-- "it crashes when I delete or modify tracks".
--
-- Rows now store the GUID, which survives delete / undo / reorder / reload, and
-- the pointer is resolved and validated immediately before every use.
local function rebuild()
  rows = {}
  for i=0, r.CountTracks(0)-1 do
    local t = r.GetTrack(0,i)
    if t then
      local nm = tName(t)
      local rgb, why = decide(t, nm)
      rows[#rows+1] = { guid=r.GetTrackGUID(t), name=nm, kind=why, want=rgb,
                        depth=r.GetMediaTrackInfo_Value(t,"I_FOLDERDEPTH"), sel=r.IsTrackSelected(t) }
    end
  end
end

-- GUID -> live pointer, rebuilt fresh each frame, never stored.
local function liveMap()
  local m = {}
  for i=0, r.CountTracks(0)-1 do
    local t = r.GetTrack(0,i)
    if t then m[r.GetTrackGUID(t)] = t end
  end
  return m
end

-- Resolve one row to a validated, live pointer.  nil is a normal answer: it
-- means the user deleted that track and the row is now a tombstone.
local function rowTrack(row, map)
  local t = map and map[row.guid] or nil
  if t and r.ValidatePtr2(0, t, "MediaTrack*") then return t end
  return nil
end

local function pcol(i) local c=PALETTES[paletteIdx].cols; return c[((i-1)%#c)+1] end

--------------------------------------------------------------------------------
-- markers & regions
--------------------------------------------------------------------------------
local function applyMarkers(silent)
  local i, painted = 0, 0
  local total = 0
  while true do
    local ok, isrgn, pos, rgnend, name, idx, col = r.EnumProjectMarkers3(0, i)
    if not ok or ok == 0 then break end
    total = total + 1
    local kind = isrgn and "region" or "marker"
    for _,ru in ipairs(MYRULES) do
      if ru.on and ru.kind == kind and ruleMatchesName(ru, name or "") then
        local native = r.ColorToNative(clamp(ru.rgb[1]),clamp(ru.rgb[2]),clamp(ru.rgb[3])) | 0x1000000
        r.SetProjectMarkerByIndex2(0, i, isrgn, pos, rgnend, idx, name, native, 0)
        painted = painted + 1
        break
      end
    end
    i = i + 1
  end
  if not silent then log(("Markers/regions: coloured %d of %d."):format(painted, total)) end
  return painted
end

--------------------------------------------------------------------------------
-- MODE 1: the rule engine
--------------------------------------------------------------------------------
local function applyRules(silent)
  r.Undo_BeginBlock()
  local famOf, stack = {}, {}
  for i=0, r.CountTracks(0)-1 do
    local t = r.GetTrack(0,i)
    local d = r.GetMediaTrackInfo_Value(t,"I_FOLDERDEPTH")
    if #stack>0 then famOf[t] = stack[#stack] end
    if d==1 then stack[#stack+1] = { top=t, n={} } end
    if d<0 then for _=1,-d do if #stack>0 then table.remove(stack) end end end
  end
  local counts, painted, unknown = {}, 0, {}
  for _,t in ipairs(scopeTracks()) do
    local nm = tName(t)
    local c, why = decide(t, nm)
    if c then
      if why ~= "bus" and why ~= "group" and why ~= "return" and shadeChildren and famOf[t] then
        -- siblings of the SAME family inside a folder step gently lighter,
        -- so a kit reads as one colour with depth instead of five flat blocks
        local f = famOf[t]
        f.n[why] = (f.n[why] or 0) + 1
        c = shade(c, math.min(0.045 * ((f.n[why]-1) % 5), 0.18))
      end
      setCol(t, c); painted = painted + 1
      counts[why] = (counts[why] or 0) + 1
    else
      unknown[#unknown+1] = nm
    end
  end
  local mk = doMarkers and applyMarkers(true) or 0
  r.Undo_EndBlock("Palette & Look: apply colour rules",-1)
  r.TrackList_AdjustWindows(false); r.UpdateArrange()
  if not silent then
    local parts = {}
    for _,k in ipairs(ROLE_ORDER) do if counts[k] then parts[#parts+1] = k.." "..counts[k] end end
    for k,v in pairs(counts) do if k:find("^rule:") then parts[#parts+1] = k:sub(6).." "..v end end
    log(("Painted %d track(s)%s  [%s]"):format(painted, mk>0 and (" + "..mk.." marker(s)") or "", table.concat(parts,", ")))
    if #unknown>0 then
      local u = {}
      for i=1,math.min(#unknown,6) do u[#u+1]=unknown[i] end
      log("  no rule matched ("..#unknown.."): "..table.concat(u,", ")..(#unknown>6 and " ..." or ""))
    end
  end
  rebuild()
end

--------------------------------------------------------------------------------
-- other modes
--------------------------------------------------------------------------------
local function applyByRole()
  r.Undo_BeginBlock()
  local map, idx = {}, 0
  for _,t in ipairs(scopeTracks()) do
    local nm = tName(t)
    local key = select(2, decide(t, nm)) or ("~"..baseKey(nm))
    if not map[key] then idx=idx+1; map[key]=pcol(idx) end
    setCol(t, map[key])
  end
  r.Undo_EndBlock("Palette & Look: colour by role",-1)
  r.TrackList_AdjustWindows(false); r.UpdateArrange()
  log("Coloured by instrument role using "..PALETTES[paletteIdx].name..".")
  rebuild()
end

local function applyByFolder()
  r.Undo_BeginBlock()
  local stack, fam = {}, 0
  for i=0, r.CountTracks(0)-1 do
    local t = r.GetTrack(0,i)
    local nm = tName(t)
    local d = r.GetMediaTrackInfo_Value(t,"I_FOLDERDEPTH")
    if d==1 or (isBusName(nm) and d>=1) then
      fam = fam + 1
      local c = pcol(fam)
      setCol(t, c)
      if d==1 then stack[#stack+1] = { c=c, n=0 } end
    else
      if #stack>0 then
        local top = stack[#stack]
        setCol(t, shade(top.c, math.min(0.10 + top.n*0.09, 0.6)))
        top.n = top.n + 1
      else
        setCol(t, pcol(fam+1))
      end
    end
    if d<0 then for _=1,-d do if #stack>0 then table.remove(stack) end end end
  end
  r.Undo_EndBlock("Palette & Look: colour by folder",-1)
  r.TrackList_AdjustWindows(false); r.UpdateArrange()
  log("Coloured by folder: each BUS a family hue, children shaded.")
  rebuild()
end

local function applySurprise()
  r.Undo_BeginBlock()
  local g = {}
  for _,t in ipairs(scopeTracks()) do
    local k = baseKey(tName(t))
    if not g[k] then g[k] = randRGB() end
    setCol(t, g[k])
  end
  r.Undo_EndBlock("Palette & Look: surprise colours",-1)
  r.TrackList_AdjustWindows(false); r.UpdateArrange()
  log("Surprise! Random colours grouped by name. Hit again to re-roll.")
  rebuild()
end

--------------------------------------------------------------------------------
-- tools
--------------------------------------------------------------------------------
local function applyGradient()
  r.Undo_BeginBlock()
  local list = scopeTracks()
  for i,t in ipairs(list) do
    local f = (#list<2) and 0 or (i-1)/(#list-1)
    setCol(t, lerp(gradA, gradB, f))
  end
  r.Undo_EndBlock("Palette & Look: gradient",-1)
  r.TrackList_AdjustWindows(false); r.UpdateArrange()
  log(("Gradient %s -> %s across %d track(s)."):format(hexOf(gradA), hexOf(gradB), #list)); rebuild()
end

local function nudge(kind, amt)
  r.Undo_BeginBlock()
  local n = 0
  for _,t in ipairs(scopeTracks()) do
    local c = getRGB(t)
    if c then
      local h,s,l = rgb2hsl(c)
      if kind=="light" then l = math.max(0, math.min(1, l+amt))
      elseif kind=="sat" then s = math.max(0, math.min(1, s+amt))
      elseif kind=="hue" then h = (h+amt) % 1 end
      setCol(t, hsl2rgb(h,s,l)); n = n + 1
    end
  end
  r.Undo_EndBlock("Palette & Look: nudge colour",-1)
  r.TrackList_AdjustWindows(false); r.UpdateArrange()
  log(("Nudged %s on %d track(s)."):format(kind, n)); rebuild()
end

local function copyFirstColor()
  r.Undo_BeginBlock()
  local list = scopeTracks()
  local c = list[1] and getRGB(list[1])
  if c then for i=2,#list do setCol(list[i], c) end end
  r.Undo_EndBlock("Palette & Look: match colour",-1)
  r.TrackList_AdjustWindows(false); r.UpdateArrange()
  log(c and ("Matched "..(#list-1).." track(s) to "..hexOf(c)) or "First track has no colour."); rebuild()
end

local function inheritFromParent()
  r.Undo_BeginBlock()
  local stack, n = {}, 0
  for i=0, r.CountTracks(0)-1 do
    local t = r.GetTrack(0,i)
    local d = r.GetMediaTrackInfo_Value(t,"I_FOLDERDEPTH")
    if #stack>0 then
      local top = stack[#stack]
      setCol(t, shade(top.c, math.min(0.08 + top.n*0.08, 0.55))); top.n = top.n + 1; n = n + 1
    end
    if d==1 then local c=getRGB(t) or pcol(i+1); stack[#stack+1]={c=c,n=0} end
    if d<0 then for _=1,-d do if #stack>0 then table.remove(stack) end end end
  end
  r.Undo_EndBlock("Palette & Look: inherit from parent",-1)
  r.TrackList_AdjustWindows(false); r.UpdateArrange()
  log("Children inherit their folder's colour ("..n.." track(s))."); rebuild()
end

local function clearColors()
  r.Undo_BeginBlock()
  local n = 0
  for _,t in ipairs(scopeTracks()) do r.SetTrackColor(t, 0); n=n+1 end
  r.Undo_EndBlock("Palette & Look: clear colours",-1)
  r.TrackList_AdjustWindows(false); r.UpdateArrange()
  log("Cleared colour on "..n.." track(s)."); rebuild()
end

local function applyPaletteInOrder()
  r.Undo_BeginBlock()
  local list = scopeTracks()
  for i,t in ipairs(list) do setCol(t, pcol(i)) end
  r.Undo_EndBlock("Palette & Look: palette in order",-1)
  r.TrackList_AdjustWindows(false); r.UpdateArrange()
  log("Applied "..PALETTES[paletteIdx].name.." across "..#list.." track(s)."); rebuild()
end

--------------------------------------------------------------------------------
-- naming
--------------------------------------------------------------------------------
local function prettify(s)
  s = s:gsub("%.[%a%d]+$","")
  s = s:gsub("^%s*%d+%s*[%-_%.%)]?%s*", "")
  s = s:gsub("[_%-]+"," ")
  s = s:gsub("%s*%d+%s*$","")
  return (s:gsub("%s+"," "):gsub("^%s+",""):gsub("%s+$",""))
end
local function nameFromItems()
  r.Undo_BeginBlock()
  local num, renamed = numberStart, 0
  for _,t in ipairs(scopeTracks()) do
    local newName
    if r.CountTrackMediaItems(t) > 0 then
      local tk = r.GetActiveTake(r.GetTrackMediaItem(t, 0))
      if tk then
        local src = r.GetMediaItemTake_Source(tk)
        local path = src and r.GetMediaSourceFileName(src, "") or ""
        local fn = path:match("[^/\\]+$")
        if fn and fn ~= "" then newName = prettify(fn) end
        if (not newName or newName=="") then
          local ok, tn = r.GetSetMediaItemTakeInfo_String(tk,"P_NAME","",false)
          if ok and tn ~= "" then newName = prettify(tn) end
        end
      end
    end
    if not newName or newName == "" then newName = prettify(tName(t)) end
    if newName ~= "" then
      if numberTracks then newName = string.format("%02d %s", num, newName) end
      r.GetSetMediaTrackInfo_String(t,"P_NAME", newName, true)
      renamed = renamed + 1
    end
    num = num + 1
  end
  r.Undo_EndBlock("Palette & Look: name from items",-1)
  r.TrackList_AdjustWindows(false)
  log("Renamed "..renamed.." track(s) from their first item's source."); rebuild()
end
local function nameAndColor() nameFromItems(); applyRules(); log("Name + Colour done.") end

local function stripEmoji(nm)
  for _,e in ipairs(ALL_EMOJI) do nm = nm:gsub(e.." ?", "") end
  return (nm:gsub("^%s+",""))
end
local function addEmoji()
  r.Undo_BeginBlock()
  local c=0
  for _,t in ipairs(scopeTracks()) do
    local nm = tName(t)
    local _, why = decide(t, nm)
    local key = why
    if key and key:find("^rule:") then key = roleOf(nm) end
    local e = key and ROLE_EMOJI[key]
    if e then r.GetSetMediaTrackInfo_String(t,"P_NAME", e.." "..stripEmoji(nm), true); c=c+1 end
  end
  r.Undo_EndBlock("Palette & Look: add role emoji",-1)
  r.TrackList_AdjustWindows(false); log("Added role emoji to "..c.." track(s)."); rebuild()
end
local function removeEmoji()
  r.Undo_BeginBlock()
  for _,t in ipairs(scopeTracks()) do r.GetSetMediaTrackInfo_String(t,"P_NAME", stripEmoji(tName(t)), true) end
  r.Undo_EndBlock("Palette & Look: remove emoji",-1)
  r.TrackList_AdjustWindows(false); log("Removed emoji."); rebuild()
end
local function upperBuses()
  r.Undo_BeginBlock()
  local c=0
  for i=0,r.CountTracks(0)-1 do
    local t=r.GetTrack(0,i)
    if isFolder(t) then
      local nm=tName(t)
      if nm~=nm:upper() then r.GetSetMediaTrackInfo_String(t,"P_NAME",nm:upper(),true); c=c+1 end
    end
  end
  r.Undo_EndBlock("Palette & Look: UPPERCASE buses",-1)
  r.TrackList_AdjustWindows(false); log("Uppercased "..c.." bus name(s)."); rebuild()
end

--------------------------------------------------------------------------------
-- live auto-apply
--------------------------------------------------------------------------------
local function projSig()
  local n = r.CountTracks(0)
  local acc = {n}
  for i=0,n-1 do
    local t = r.GetTrack(0,i)
    acc[#acc+1] = tName(t)..":"..math.floor(r.GetMediaTrackInfo_Value(t,"I_FOLDERDEPTH"))
  end
  return table.concat(acc,"|")
end

--------------------------------------------------------------------------------
-- theme (violet identity)
--------------------------------------------------------------------------------
local V, VH, VA = 0x8A5CF0ff, 0x9E74F5ff, 0x6E44C8ff
local BG, PANEL, TXT, MUT = 0x14121Aff, 0x1E1B28ff, 0xEDE9F5ff, 0x8B84A0ff
local PINK, PINKH = 0xE04A96ff, 0xF060A8ff
local DEAD = 0xE0455Aff   -- a row whose track has been deleted under us
local function pushTheme()
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 5)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 12, 10)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 7, 4)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), BG)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), TXT)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), V)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), VH)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), VA)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), PANEL)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), VA)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TableHeaderBg(), PANEL)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgActive(), VA)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TabActive and r.ImGui_Col_TabActive() or r.ImGui_Col_Header(), VA)
end
local function popTheme() r.ImGui_PopStyleColor(ctx,10); r.ImGui_PopStyleVar(ctx,3) end

local NOIN = r.ImGui_ColorEditFlags_NoInputs and r.ImGui_ColorEditFlags_NoInputs() or 0
local NOTT = r.ImGui_ColorEditFlags_NoTooltip and r.ImGui_ColorEditFlags_NoTooltip() or 0

--------------------------------------------------------------------------------
-- UI
--------------------------------------------------------------------------------
local function tabHeader()
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), VH)
  r.ImGui_Text(ctx, "PALETTE  &  LOOK")
  r.ImGui_PopStyleColor(ctx,1)
  r.ImGui_SameLine(ctx); r.ImGui_TextColored(ctx, MUT, "   colour from meaning")
  r.ImGui_SameLine(ctx)
  local docked = r.ImGui_IsWindowDocked(ctx)
  local dc,dv = r.ImGui_Checkbox(ctx,"Dock",docked); if dc then dockPending = dv and -1 or 0 end
  r.ImGui_SameLine(ctx)
  local lc,lv = r.ImGui_Checkbox(ctx,"LIVE",liveOn)
  if lc then liveOn=lv; liveSig=""; log(liveOn and "Live auto-colour ON - new/renamed tracks colour themselves." or "Live auto-colour off.") end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx,"Watch the project and re-apply rules whenever tracks are added or renamed") end
  r.ImGui_Separator(ctx)

  r.ImGui_TextColored(ctx, MUT, "Apply to")
  r.ImGui_SameLine(ctx)
  if r.ImGui_RadioButton(ctx, "Selection", scope=="sel") then scope="sel" end
  r.ImGui_SameLine(ctx)
  if r.ImGui_RadioButton(ctx, "Whole project", scope=="all") then scope="all" end
  r.ImGui_SameLine(ctx)
  local mc,mv = r.ImGui_Checkbox(ctx,"markers/regions too",doMarkers); if mc then doMarkers=mv end
  r.ImGui_SameLine(ctx)
  local uc,uv = r.ImGui_Checkbox(ctx,"my rules first",useMyRules); if uc then useMyRules=uv; rebuild() end

  r.ImGui_Spacing(ctx)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), PINK)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), PINKH)
  if r.ImGui_Button(ctx, "APPLY COLOUR RULES", 200, 34) then applyRules() end
  r.ImGui_PopStyleColor(ctx,2)
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx,"My rules -> families -> structure. One undo.") end
  r.ImGui_SameLine(ctx); if r.ImGui_Button(ctx, "Name from items", 140, 34) then nameFromItems() end
  r.ImGui_SameLine(ctx); if r.ImGui_Button(ctx, "Name + Colour", 130, 34) then nameAndColor() end
  r.ImGui_SameLine(ctx)
  local nc,nv = r.ImGui_Checkbox(ctx,"number",numberTracks); if nc then numberTracks=nv end
  r.ImGui_SameLine(ctx); r.ImGui_SetNextItemWidth(ctx,54)
  local sc,sv = r.ImGui_InputInt(ctx,"##start",numberStart,0,0); if sc then numberStart=math.max(1,sv) end
end

local function tabMyRules()
  r.ImGui_TextColored(ctx, MUT, "Ordered like SWS Auto Color - first match wins. These beat the families below.")
  if r.ImGui_Button(ctx, "Import my SWS rules") then
    local n, err = importSWS()
    if n then log("Imported "..n.." rule(s) from sws-autocoloricon.ini."); rebuild()
    else log("Import failed: "..tostring(err)) end
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, SWSINI) end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Export to SWS") then
    local n, bak = exportSWS()
    if n then log("Wrote "..n.." rule(s) to SWS (backup: "..tostring(bak)..").")
    else log("Export failed: "..tostring(bak)) end
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Seed from families") then
    MYRULES = {}
    for _,k in ipairs(ROLE_ORDER) do
      if k ~= "bus" and k ~= "return" then
        MYRULES[#MYRULES+1] = { on=true, kind="track", mode="role", filter=k, rgb={RULES[k][1],RULES[k][2],RULES[k][3]} }
      end
    end
    MYRULES[#MYRULES+1] = { on=true, kind="track", mode="special", filter="(receive)", rgb={RULES["return"][1],RULES["return"][2],RULES["return"][3]} }
    MYRULES[#MYRULES+1] = { on=true, kind="track", mode="special", filter="(folder)",  rgb={RULES.bus[1],RULES.bus[2],RULES.bus[3]} }
    rulesSave(); log("Seeded "..#MYRULES.." rules from the family colours."); rebuild()
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Clear all") then MYRULES = {}; rulesSave(); rebuild(); log("Cleared my rules.") end

  r.ImGui_Spacing(ctx)
  -- add row
  r.ImGui_SetNextItemWidth(ctx, 90)
  local KINDS = {"track","marker","region"}
  if r.ImGui_BeginCombo(ctx, "##k", KINDS[newKindIdx]) then
    for i,k in ipairs(KINDS) do if r.ImGui_Selectable(ctx, k, i==newKindIdx) then newKindIdx=i end end
    r.ImGui_EndCombo(ctx)
  end
  r.ImGui_SameLine(ctx); r.ImGui_SetNextItemWidth(ctx, 100)
  if r.ImGui_BeginCombo(ctx, "##m", MODES[newModeIdx]) then
    for i,m in ipairs(MODES) do if r.ImGui_Selectable(ctx, m, i==newModeIdx) then newModeIdx=i end end
    r.ImGui_EndCombo(ctx)
  end
  r.ImGui_SameLine(ctx); r.ImGui_SetNextItemWidth(ctx, 180)
  local fc, fv = r.ImGui_InputText(ctx, "##f", newFilter); if fc then newFilter = fv end
  r.ImGui_SameLine(ctx)
  local cc, cv = r.ImGui_ColorEdit3(ctx, "##nc", packRGB(newRGB), NOIN); if cc then newRGB = unpackRGB(cv) end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "+ Add rule") and newFilter ~= "" then
    local mode = MODES[newModeIdx]
    if newFilter:sub(1,1) == "(" then mode = "special" end
    table.insert(MYRULES, { on=true, kind=KINDS[newKindIdx], mode=mode, filter=newFilter, rgb={newRGB[1],newRGB[2],newRGB[3]} })
    rulesSave(); newFilter=""; rebuild(); log("Rule added.")
  end
  r.ImGui_TextColored(ctx, MUT, "specials: (folder) (receive) (send) (master) (unnamed) (any) (armed) (muted) (empty) (midi)")

  r.ImGui_Spacing(ctx)
  local flags = r.ImGui_TableFlags_Borders()|r.ImGui_TableFlags_RowBg()|r.ImGui_TableFlags_ScrollY()
  if r.ImGui_BeginTable(ctx, "mr", 7, flags, 0, 240) then
    r.ImGui_TableSetupScrollFreeze(ctx,0,1)
    r.ImGui_TableSetupColumn(ctx,"On",r.ImGui_TableColumnFlags_WidthFixed(),28)
    r.ImGui_TableSetupColumn(ctx,"Type",r.ImGui_TableColumnFlags_WidthFixed(),60)
    r.ImGui_TableSetupColumn(ctx,"Match",r.ImGui_TableColumnFlags_WidthFixed(),90)
    r.ImGui_TableSetupColumn(ctx,"Filter",r.ImGui_TableColumnFlags_WidthStretch())
    r.ImGui_TableSetupColumn(ctx,"Colour",r.ImGui_TableColumnFlags_WidthFixed(),56)
    r.ImGui_TableSetupColumn(ctx,"Hits",r.ImGui_TableColumnFlags_WidthFixed(),42)
    r.ImGui_TableSetupColumn(ctx,"",r.ImGui_TableColumnFlags_WidthFixed(),74)
    r.ImGui_TableHeadersRow(ctx)
    local del, mv = nil, nil
    for i,ru in ipairs(MYRULES) do
      r.ImGui_TableNextRow(ctx); r.ImGui_PushID(ctx, 1000+i)
      r.ImGui_TableNextColumn(ctx)
      local oc,ov = r.ImGui_Checkbox(ctx,"##on",ru.on); if oc then ru.on=ov; rulesSave(); rebuild() end
      r.ImGui_TableNextColumn(ctx); r.ImGui_Text(ctx, ru.kind)
      r.ImGui_TableNextColumn(ctx)
      r.ImGui_SetNextItemWidth(ctx, 84)
      if r.ImGui_BeginCombo(ctx, "##mm", ru.mode) then
        for _,m in ipairs(MODES) do if r.ImGui_Selectable(ctx, m, m==ru.mode) then ru.mode=m; rulesSave(); rebuild() end end
        if r.ImGui_Selectable(ctx, "special", ru.mode=="special") then ru.mode="special"; rulesSave(); rebuild() end
        r.ImGui_EndCombo(ctx)
      end
      r.ImGui_TableNextColumn(ctx)
      r.ImGui_SetNextItemWidth(ctx, -1)
      local tc,tv = r.ImGui_InputText(ctx,"##ff",ru.filter); if tc then ru.filter=tv; rulesSave(); rebuild() end
      r.ImGui_TableNextColumn(ctx)
      local rc,rv = r.ImGui_ColorEdit3(ctx,"##rc",packRGB(ru.rgb),NOIN); if rc then ru.rgb=unpackRGB(rv); rulesSave(); rebuild() end
      r.ImGui_TableNextColumn(ctx)
      local hits = 0
      if ru.kind == "track" then
        for _,row in ipairs(rows) do if row.kind == "rule:"..ru.filter then hits = hits + 1 end end
      end
      r.ImGui_TextColored(ctx, hits>0 and VH or MUT, tostring(hits))
      r.ImGui_TableNextColumn(ctx)
      if r.ImGui_SmallButton(ctx,"^") then mv = {i,-1} end
      r.ImGui_SameLine(ctx); if r.ImGui_SmallButton(ctx,"v") then mv = {i,1} end
      r.ImGui_SameLine(ctx); if r.ImGui_SmallButton(ctx,"x") then del = i end
      r.ImGui_PopID(ctx)
    end
    r.ImGui_EndTable(ctx)
    if del then table.remove(MYRULES, del); rulesSave(); rebuild() end
    if mv then
      local i, d = mv[1], mv[2]
      if MYRULES[i+d] then MYRULES[i], MYRULES[i+d] = MYRULES[i+d], MYRULES[i]; rulesSave(); rebuild() end
    end
  end
  if r.ImGui_Button(ctx, "Colour markers & regions now") then applyMarkers() end
end

local function tabFamilies()
  r.ImGui_TextColored(ctx, MUT, "The fallback brain. Synonym-aware: 'Gtr Dist L', 'OD Rhythm', 'Les Paul' all read as guitar.")
  local changed = false
  for i,k in ipairs(ROLE_ORDER) do
    local c = RULES[k]
    local rc, rv = r.ImGui_ColorEdit3(ctx, k.."##rule", packRGB(c), NOIN)
    if rc then RULES[k] = unpackRGB(rv); changed = true end
    if i % 4 ~= 0 and i < #ROLE_ORDER then r.ImGui_SameLine(ctx) end
  end
  if changed then saveRules(); rebuild() end
  r.ImGui_Spacing(ctx)
  if r.ImGui_Button(ctx, "Reset to my SWS colours") then
    for k,v in pairs(DEFAULTS) do RULES[k] = {v[1],v[2],v[3]} end
    saveRules(); rebuild(); log("Families reset to your SWS colours.")
  end
  r.ImGui_SameLine(ctx)
  local xc,xv = r.ImGui_Checkbox(ctx,"shade children under their folder",shadeChildren); if xc then shadeChildren=xv end
end

local function tabPalettes()
  r.ImGui_TextColored(ctx, MUT, "Active: "..PALETTES[paletteIdx].name)
  for i,P in ipairs(PALETTES) do
    local sel = (i==paletteIdx)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), sel and VA or PANEL)
    if r.ImGui_Button(ctx, P.name.."##p"..i, 118, 0) then paletteIdx = i end
    r.ImGui_PopStyleColor(ctx,1)
    r.ImGui_SameLine(ctx)
    for j=1,#P.cols do
      r.ImGui_ColorButton(ctx, "##s"..i.."_"..j, u32(P.cols[j]), NOTT, 14, 16)
      if j<#P.cols then r.ImGui_SameLine(ctx, 0, 1) end
    end
  end
  r.ImGui_Spacing(ctx)
  if r.ImGui_Button(ctx, "Colour by ROLE", 140, 26) then applyByRole() end
  r.ImGui_SameLine(ctx); if r.ImGui_Button(ctx, "Colour by FOLDER", 150, 26) then applyByFolder() end
  r.ImGui_SameLine(ctx); if r.ImGui_Button(ctx, "Palette in order", 140, 26) then applyPaletteInOrder() end
  r.ImGui_SameLine(ctx)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xC04AB0ff)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xD85CC8ff)
  if r.ImGui_Button(ctx, "Surprise (re-roll)", 150, 26) then applySurprise() end
  r.ImGui_PopStyleColor(ctx,2)
end

local function tabTools()
  r.ImGui_TextColored(ctx, MUT, "Gradient across the selection, in track order")
  local ac,av = r.ImGui_ColorEdit3(ctx,"from##ga",packRGB(gradA),NOIN); if ac then gradA=unpackRGB(av) end
  r.ImGui_SameLine(ctx)
  local bc,bv = r.ImGui_ColorEdit3(ctx,"to##gb",packRGB(gradB),NOIN); if bc then gradB=unpackRGB(bv) end
  r.ImGui_SameLine(ctx); if r.ImGui_Button(ctx,"Apply gradient",130,0) then applyGradient() end
  r.ImGui_SameLine(ctx); if r.ImGui_Button(ctx,"Swap") then gradA,gradB = gradB,gradA end

  r.ImGui_Spacing(ctx); r.ImGui_Separator(ctx)
  r.ImGui_TextColored(ctx, MUT, "Nudge what is already there")
  if r.ImGui_Button(ctx,"Lighter") then nudge("light", 0.07) end
  r.ImGui_SameLine(ctx); if r.ImGui_Button(ctx,"Darker") then nudge("light",-0.07) end
  r.ImGui_SameLine(ctx); if r.ImGui_Button(ctx,"More colour") then nudge("sat", 0.10) end
  r.ImGui_SameLine(ctx); if r.ImGui_Button(ctx,"Less colour") then nudge("sat",-0.10) end
  r.ImGui_SameLine(ctx); if r.ImGui_Button(ctx,"Hue +") then nudge("hue", 0.04) end
  r.ImGui_SameLine(ctx); if r.ImGui_Button(ctx,"Hue -") then nudge("hue",-0.04) end

  r.ImGui_Spacing(ctx); r.ImGui_Separator(ctx)
  r.ImGui_TextColored(ctx, MUT, "Structure & housekeeping")
  if r.ImGui_Button(ctx,"Match to first selected",180,0) then copyFirstColor() end
  r.ImGui_SameLine(ctx); if r.ImGui_Button(ctx,"Children inherit folder",180,0) then inheritFromParent() end
  r.ImGui_SameLine(ctx); if r.ImGui_Button(ctx,"Clear colours",130,0) then clearColors() end

  r.ImGui_Spacing(ctx); r.ImGui_Separator(ctx)
  r.ImGui_TextColored(ctx, MUT, "Names")
  if r.ImGui_Button(ctx, "Add role emoji") then addEmoji() end
  r.ImGui_SameLine(ctx); if r.ImGui_Button(ctx, "Remove emoji") then removeEmoji() end
  r.ImGui_SameLine(ctx); if r.ImGui_Button(ctx, "UPPERCASE buses") then upperBuses() end
  r.ImGui_SameLine(ctx); if r.ImGui_Button(ctx, "Refresh") then rebuild() end
end

local function tabTracks()
  r.ImGui_TextColored(ctx, MUT, "now  ->  what the rules want.  Grey FAMILY = nothing matched yet.")
  local flags = r.ImGui_TableFlags_Borders()|r.ImGui_TableFlags_RowBg()|r.ImGui_TableFlags_ScrollY()
  local _,availH = r.ImGui_GetContentRegionAvail(ctx)
  if r.ImGui_BeginTable(ctx, "trk", 5, flags, 0, math.max(140, availH-10)) then
    r.ImGui_TableSetupScrollFreeze(ctx,0,1)
    r.ImGui_TableSetupColumn(ctx,"#",r.ImGui_TableColumnFlags_WidthFixed(),30)
    r.ImGui_TableSetupColumn(ctx,"Now",r.ImGui_TableColumnFlags_WidthFixed(),34)
    r.ImGui_TableSetupColumn(ctx,"Want",r.ImGui_TableColumnFlags_WidthFixed(),34)
    r.ImGui_TableSetupColumn(ctx,"Track",r.ImGui_TableColumnFlags_WidthStretch())
    r.ImGui_TableSetupColumn(ctx,"Matched by",r.ImGui_TableColumnFlags_WidthFixed(),150)
    r.ImGui_TableHeadersRow(ctx)
    local map = liveMap()          -- resolved once per frame, discarded after
    for i,row in ipairs(rows) do
      local live = rowTrack(row, map)
      r.ImGui_TableNextRow(ctx); r.ImGui_PushID(ctx,i)
      r.ImGui_TableNextColumn(ctx); r.ImGui_TextColored(ctx, MUT, tostring(i))
      r.ImGui_TableNextColumn(ctx)
      if live then r.ImGui_ColorButton(ctx,"##c",trackU32(live),NOTT,20,16)
      else r.ImGui_TextColored(ctx, DEAD, "x") end
      r.ImGui_TableNextColumn(ctx)
      if row.want and live then
        if r.ImGui_ColorButton(ctx,"##w",u32(row.want),NOTT,20,16) then
          r.Undo_BeginBlock(); setCol(live,row.want); r.Undo_EndBlock("Palette & Look: colour one track",-1)
          r.TrackList_AdjustWindows(false); rebuild()
        end
        if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx,"Click to apply "..hexOf(row.want).." to just this track") end
      else r.ImGui_TextColored(ctx, MUT, " -") end
      r.ImGui_TableNextColumn(ctx)
      local indent = ""
      if row.depth and row.depth < 1 then indent = "" end
      if not live then r.ImGui_TextColored(ctx, DEAD, indent..row.name.."   (deleted)")
      elseif row.kind=="bus" then r.ImGui_TextColored(ctx, VH, indent..row.name)
      else r.ImGui_Text(ctx, indent..row.name) end
      r.ImGui_TableNextColumn(ctx)
      local label = row.kind or "-"
      r.ImGui_TextColored(ctx, row.kind and (row.kind:find("^rule:") and PINKH or V) or MUT, label)
      r.ImGui_PopID(ctx)
    end
    r.ImGui_EndTable(ctx)
  end
end

local function frame()
  tabHeader()
  r.ImGui_Spacing(ctx)
  if r.ImGui_BeginTabBar(ctx, "tabs") then
    if r.ImGui_BeginTabItem(ctx, "My rules") then r.ImGui_Spacing(ctx); tabMyRules(); r.ImGui_EndTabItem(ctx) end
    if r.ImGui_BeginTabItem(ctx, "Families")  then r.ImGui_Spacing(ctx); tabFamilies(); r.ImGui_EndTabItem(ctx) end
    if r.ImGui_BeginTabItem(ctx, "Palettes")  then r.ImGui_Spacing(ctx); tabPalettes(); r.ImGui_EndTabItem(ctx) end
    if r.ImGui_BeginTabItem(ctx, "Tools")     then r.ImGui_Spacing(ctx); tabTools();    r.ImGui_EndTabItem(ctx) end
    if r.ImGui_BeginTabItem(ctx, "Tracks")    then r.ImGui_Spacing(ctx); tabTracks();   r.ImGui_EndTabItem(ctx) end
    if r.ImGui_BeginTabItem(ctx, "Log")       then
      r.ImGui_Spacing(ctx)
      local cb = r.ImGui_ChildFlags_Border and r.ImGui_ChildFlags_Border() or 0
      if r.ImGui_BeginChild(ctx,"log",0,0,cb) then
        for _,l in ipairs(logLines) do r.ImGui_Text(ctx,l) end
        r.ImGui_EndChild(ctx)
      end
      r.ImGui_EndTabItem(ctx)
    end
    r.ImGui_EndTabBar(ctx)
  end
end

--------------------------------------------------------------------------------
rebuild()
local function loop()
  -- WATCHDOG.  Runs before anything reads a row.  If a track was added, deleted,
  -- renamed or reordered, resync the list now so the table never renders stale
  -- data.  Throttled to ~4Hz because the signature walks every track, and this
  -- has to stay cheap on a 452-track session.
  local now = r.time_precise()
  if now - lastSigT > 0.25 then
    lastSigT = now
    local sig = projSig()
    if sig ~= lastSig then lastSig = sig; rebuild() end
  end

  if liveOn then
    local now = r.time_precise()
    if now - liveT > 0.4 then
      liveT = now
      local sig = projSig()
      if sig ~= liveSig then
        liveSig = sig
        local keep = scope; scope = "all"
        applyRules(true)
        scope = keep
      end
    end
  end
  if dockPending~=nil then r.ImGui_SetNextWindowDockID(ctx,dockPending); dockPending=nil end
  if firstFrame then r.ImGui_SetNextWindowSize(ctx,900,700); firstFrame=false end
  pushTheme()
  local vis,open = r.ImGui_Begin(ctx,'Palette & Look',true)
  if vis then
    local ok,err = pcall(frame)
    if not ok then r.ImGui_TextColored(ctx,0xE06A5Aff,"Error: "..tostring(err)) end
    r.ImGui_End(ctx)
  end
  popTheme()
  if open then r.defer(loop) end
end
r.defer(loop)
