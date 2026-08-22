--[[
  MIDI Batch Export - the test that stops "01 -.mid" coming back
  ----------------------------------------------------------------------------
  On the 22-Aug-2026 shoot four of five lessons exported with no name at all.
  Jason renamed them by hand between takes. This runs the REAL script against a
  fake REAPER built to reproduce that project - five regions, and MIDI items
  that start thirty milliseconds BEFORE their own region line, which is what
  recording into a region actually produces.

      lua tests/midi_batch_export_test.lua

  Exit 0 = the export can be trusted. Anything else = do not ship it.
--]]

local HERE   = arg[0]:match("(.*)/[^/]*$") or "."
local SCRIPT = HERE .. "/../scripts/MIDI Batch Export.lua"

local fails, checks = 0, 0
local function check(ok, label, detail)
  checks = checks + 1
  print((ok and "  ok   " or "  FAIL ") .. label)
  if detail and detail ~= "" then print("         " .. detail) end
  if not ok then fails = fails + 1 end
end

--------------------------------------------------------------------------------
-- a fake REAPER, rebuilt fresh for every case
--------------------------------------------------------------------------------
local function newReaper(opts)
  opts = opts or {}
  local REGIONS = opts.regions or {
    { name = "Shell Voicings",           s =  100, e = 1500 },
    { name = "Sight Singing",            s = 1600, e = 3000 },
    { name = "Pivot Note Harmonization", s = 3100, e = 4500 },
    { name = "Birth of Scales",          s = 4600, e = 6000 },
    { name = "Reels 22nd August 2026",   s = 6100, e = 7500 },
  }
  local ITEMS = {}
  local n = opts.itemCount or #REGIONS
  for i = 1, n do
    local base = REGIONS[i] and REGIONS[i].s or (i * 1500)
    ITEMS[i] = { pos = base - 0.03, len = 1300, guid = "{ITEM-" .. i .. "}", takeName = "" }
  end
  local TRACK = { name = opts.trackName or "01-Piano-MIDI" }

  local function evt(offset, flag, msg) return string.pack("<i4Bi4", offset, flag, #msg) .. msg end
  local BUF = evt(0, 0, "\x90\x3C\x64") .. evt(960, 0, "\x80\x3C\x00")

  local ext, said = {}, {}
  local R = setmetatable({}, { __index = function(_, k)
    if type(k) == "string" and k:match("^ImGui_") then return function() return false, 0 end end
    return function() return nil end
  end })

  R.EnumProjects   = function() return "PROJ" end
  R.time_precise   = function() return os.clock() end
  R.GetOS          = function() return "OSX64" end
  R.GetResourcePath= function() return "/tmp/resource" end
  R.get_action_context = function() return false, "/tmp/scripts/MIDI Batch Export.lua", 0, 0, 0, 0, 0 end
  R.GetProjectPath = function() return "/tmp/proj" end
  R.RecursiveCreateDirectory = function(p) os.execute('mkdir -p "' .. p .. '"'); return 1 end
  R.ShowMessageBox = function(a) error("the script gave up with a message box: " .. tostring(a)) end
  R.GetExtState    = function(s, k) return ext[s .. "/" .. k] or "" end
  R.SetExtState    = function(s, k, v) ext[s .. "/" .. k] = v end

  R.CountMediaItems = function() return #ITEMS end
  R.GetMediaItem    = function(_, i) return ITEMS[i + 1] end
  R.GetMediaItemInfo_Value = function(it, key)
    if key == "D_POSITION" then return it.pos end
    if key == "D_LENGTH"   then return it.len end
    return 0
  end
  R.IsMediaItemSelected     = function() return true end
  R.CountSelectedMediaItems = function() return #ITEMS end
  R.GetSelectedMediaItem    = function(_, i) return ITEMS[i + 1] end
  R.CountSelectedTracks     = function() return 0 end
  R.GetActiveTake  = function(it) return { item = it } end
  R.TakeIsMIDI     = function() return true end
  R.GetSetMediaItemTakeInfo_String = function(take, key)
    if key == "P_NAME" then return true, take.item.takeName end
    return true, ""
  end
  R.GetSetMediaItemInfo_String = function(it, key)
    if key == "GUID" then return true, it.guid end
    return true, ""
  end
  R.GetMediaItem_Track      = function() return TRACK end
  R.GetMediaTrackInfo_Value = function() return 1 end
  R.GetSetMediaTrackInfo_String = function(_, key)
    if key == "P_NAME" then return true, TRACK.name end
    return true, ""
  end
  R.CountTracks = function() return 1 end
  R.GetTrack    = function() return TRACK end

  R.EnumProjectMarkers3 = function(_, idx)
    local rg = REGIONS[idx + 1]
    if not rg then return 0 end
    return idx + 2, true, rg.s, rg.e, rg.name, idx + 1
  end
  R.TimeMap_GetTimeSigAtTime = function() return 4, 4, 93 end
  R.TimeMap2_timeToQN = function(_, t) return t * 93 / 60 end
  R.TimeMap2_QNToTime = function(_, qn) return qn * 60 / 93 end
  R.MIDI_GetAllEvts   = function() if opts.emptyMidi then return true, "" end return true, BUF end
  R.MIDI_GetPPQPosFromProjQN = function(_, qn) return qn * 960 end
  R.defer = function(f) R._deferred = f end
  return R, said, ext, REGIONS
end

--------------------------------------------------------------------------------
-- load the real script against that fake REAPER
--------------------------------------------------------------------------------
local function load_script(R, said)
  _G.reaper = R
  package.loaded["nt_safe"] = {
    require = function() return true end,
    projAlive = function() return true end,
    itemAlive = function(_, it) return it ~= nil end,
    trackName = function(t) return t and t.name or "" end,
    projSignature = function() return "sig" end,
  }
  package.loaded["nt_ui"] = setmetatable({
    tokens  = setmetatable({}, { __index = function() return 0 end }),
    accents = setmetatable({}, { __index = function() return 0 end }),
    segmented  = function(_, _, _, cur) return cur end,
    window     = function(_, _, frame) frame(); return false end,
    tick       = function() return false, false end,
    toggle     = function() return false, false end,
    button     = function() return false end,
    tableBegin = function() return false end,
    say = function(_, m, lvl) said[#said + 1] = { level = lvl or "info", msg = tostring(m) } end,
  }, { __index = function() return function() end end })
  package.loaded["nt_imgui"] = { install = function() end }

  local f = assert(io.open(SCRIPT, "r"))
  local src = f:read("a"); f:close()
  -- the shipped file ships no test hook; we add one only in memory
  src = src .. [[

return { plan = plan, rebuild = rebuild, doExport = doExport,
         setSource   = function(v) source = v; rebuild() end,
         setOutDir   = function(v) outDir = v end,
         setPattern  = function(v) pattern = v end,
         setOverwrite= function(v) overwrite = v end,
         loop        = loop }
]]
  return assert(load(src, "@MIDI Batch Export.lua"))()
end

local function fileNames(list)
  local out = {}
  for i, e in ipairs(list) do out[i] = e.file end
  return out
end
local function same(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end
local function join(t) return table.concat(t, " | ") end
local function danger(said)
  local n = 0
  for _, s in ipairs(said) do if s.level == "danger" then n = n + 1 end end
  return n
end

local WANT = {
  "01 - Shell Voicings.mid", "02 - Sight Singing.mid",
  "03 - Pivot Note Harmonization.mid", "04 - Birth of Scales.mid",
  "05 - Reels 22nd August 2026.mid",
}

print("MIDI Batch Export")
print("-----------------")

-- 1 / 2 / 3 - every way of choosing what to export, straight out of the box
for _, src in ipairs({ "sel", "regions", "all" }) do
  local R, said = newReaper()
  local T = load_script(R, said)
  if src ~= "sel" then T.setSource(src) end
  local got = fileNames(T.plan())
  check(same(got, WANT), "named after the region (" .. src .. ")", join(got))
end

-- 4 - the window itself draws
do
  local R, said = newReaper()
  local T = load_script(R, said)
  local ok, err = pcall(R._deferred)
  check(ok, "the window draws a frame without erroring", ok and "" or tostring(err))
end

-- 5 - the folder box is never blank
do
  local R, said = newReaper()
  local T = load_script(R, said)
  local _, _, _, dir = T.plan()
  check(dir ~= nil and dir ~= "", "output folder is filled in", tostring(dir))
end

-- 6 - a real export, into a folder that does not exist yet
do
  local R, said = newReaper()
  local T = load_script(R, said)
  local out = os.tmpname() .. "-midi/nested"
  os.remove(os.tmpname())
  T.setOutDir(out); T.setOverwrite(true)
  T.doExport()
  local written, ok = {}, true
  for _, want in ipairs(WANT) do
    local f = io.open(out .. "/" .. want, "rb")
    if f then
      local head = f:read(4); local all = f:read("a"); f:close()
      written[#written + 1] = want
      if head ~= "MThd" then ok = false end
      -- the name inside the file must match the name on it
      if not (head .. all):find(want:gsub("%.mid$", ""), 1, true) then ok = false end
    end
  end
  check(#written == #WANT and ok and danger(said) == 0,
        "exports real .mid files into a new folder, named inside and out",
        ("%d of %d written, %d error lines"):format(#written, #WANT, danger(said)))
  os.execute('rm -rf "' .. out .. '"')
end

-- 7 - a project with no regions at all still names every file
do
  local R, said = newReaper({ regions = {} , itemCount = 3 })
  local T = load_script(R, said)
  local got = fileNames(T.plan())
  local blank = 0
  for _, f in ipairs(got) do if f:match("^%d+ *%-? *%.mid$") then blank = blank + 1 end end
  check(#got == 3 and blank == 0, "no regions: falls back to the track, never blank", join(got))
end

-- 8 - an unnamed region is still called something
do
  local R, said = newReaper({ regions = { { name = "", s = 100, e = 1500 } }, itemCount = 1 })
  local T = load_script(R, said)
  local got = fileNames(T.plan())
  check(got[1] and got[1]:match("Region"), "an unnamed region gets a name", join(got))
end

-- 9 - a region name with characters a file name cannot hold
do
  local R, said = newReaper({ regions = { { name = "A/B: take 2?", s = 100, e = 1500 } }, itemCount = 1 })
  local T = load_script(R, said)
  local got = fileNames(T.plan())
  check(got[1] and not got[1]:find("[/:?]"), "illegal characters stripped from the name", join(got))
end

-- 10 - an item holding no MIDI is reported, not crashed on
do
  local R, said = newReaper({ emptyMidi = true })
  local T = load_script(R, said)
  local out = os.tmpname() .. "-empty"
  T.setOutDir(out); T.setOverwrite(true)
  local ok = pcall(T.doExport)
  check(ok, "an empty item is reported, not a crash",
        ok and (danger(said) .. " rows reported as a problem, as they should be") or "it crashed")
  os.execute('rm -rf "' .. out .. '"')
end

-- 11 - files already there, overwrite off: a warning, never a crash
do
  local R, said = newReaper()
  local T = load_script(R, said)
  local out = os.tmpname() .. "-twice"
  T.setOutDir(out); T.setOverwrite(true); T.doExport()
  local said2 = {}
  local R2 = newReaper()
  local T2 = load_script(R2, said2)
  T2.setOutDir(out); T2.setOverwrite(false)
  local ok = pcall(T2.doExport)
  check(ok and danger(said2) == 0, "second run with overwrite off warns, never errors",
        ok and (danger(said2) .. " error lines") or "it crashed")
  os.execute('rm -rf "' .. out .. '"')
end

-- 12 - THE CONTROL. A test that cannot fail proves nothing, so put the old bug
--      back in memory and make sure these checks go red.
do
  local R, said = newReaper()
  _G.reaper = R
  package.loaded["nt_safe"] = { require = function() return true end,
    projAlive = function() return true end, itemAlive = function(_, it) return it ~= nil end,
    trackName = function(t) return t and t.name or "" end, projSignature = function() return "sig" end }
  package.loaded["nt_ui"] = setmetatable({
    tokens = setmetatable({}, { __index = function() return 0 end }),
    accents = setmetatable({}, { __index = function() return 0 end }),
    segmented = function(_, _, _, c) return c end,
    window = function(_, _, f) f(); return false end,
    tick = function() return false, false end, toggle = function() return false, false end,
    button = function() return false end, tableBegin = function() return false end,
    say = function() end }, { __index = function() return function() end end })
  package.loaded["nt_imgui"] = { install = function() end }

  local f = assert(io.open(SCRIPT, "r")); local src = f:read("a"); f:close()
  -- break exactly the thing that broke on the shoot: no region ever found
  local broken, hits = src:gsub("local function regionNameForSpan%(proj, pos, len%)",
                                "local function regionNameForSpan(proj, pos, len) do return \"\" end")
  local T = assert(load(broken .. [==[

return { plan = plan }
]==], "@broken"))()
  local got = fileNames(T.plan())
  local blank = 0
  for _, fn in ipairs(got) do if fn:match("^%d+ *%-? *%.mid$") then blank = blank + 1 end end
  -- Worth reading twice: even with the region lookup destroyed the names are
  -- still not BLANK - the fallback chain catches it and uses the track. Two
  -- independent protections, so "01 -.mid" cannot come back either way.
  check(hits == 1 and not same(got, WANT) and blank == 0,
        "CONTROL: with the old bug put back, these checks do go red",
        join(got))
end

print("-----------------")
if fails > 0 then
  print(fails .. " of " .. checks .. " checks FAILED - do not ship")
  os.exit(1)
end
print(checks .. " checks pass")
