-- @description Stem Print & Handoff
-- @version 2.1.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about Print stems four ways (raw / to the bus / through master / fully wet) and put the
--   session back exactly as it was. Optionally builds a plugin-free mirror tab
--   with the printed files on it, ready to hand to anyone on any DAW.
--   Requires the "Shared Libraries" package from this same repository
--   (right-click the repository in ReaPack > Install All).
-- @changelog
--   2.1.0 - print modes are now the four you actually use: Raw (no plugins, your
--           fader), To the bus (plugins on, fader + pan, sends muted), Through the
--           master (your "Stems Default" preset: each stem via the master bus and its
--           plugins) and Fully wet (solo-in-place with its reverbs/delays). Unity
--           fader / centre pan is now an option that defaults OFF.
--   2.0.0 - new shared look (nt_ui): header, one status line + log, confirm
--           dialogs, system font. "Mirror to new tab" now actually works.
--           "Fully wet" now actually prints (one isolated pass per stem).
--           Render tail is applied via the real RENDER_TAILFLAG/RENDER_TAILMS
--           keys; stems no longer come with an unwanted master mix file.
--           Plugin-free clone keeps items and receives (only FX removed).
--   1.0.0 - first public release.

--[[
  Stem Print & Handoff  -  REAPER / ReaImGui
  ------------------------------------------------------------------------------
  Prepares a session to hand to another engineer / another DAW.

    Print stems     Bounce the tracks and buses you tick to WAV at the project's
                    own sample rate, at your fader and pan (or at unity / centre if you ask),
                    then restore every fader, pan, mute, send-mute and
                    FX-bypass exactly. Everything happens inside one undo point.

        Raw            no plugins, the fader and pan as they are
        To the bus     plugins on, fader + pan, every send muted (no reverb/delay)
        Through master each stem alone through the master bus and its plugins
        Fully wet      each stem solo-in-place, with its reverbs and delays

    Mirror tab      After the print, a new project tab with the same track
                    names, colours and folders - no plugins - and each printed
                    file already sitting on its track. That tab is the handoff.

    Uppercase buses Every folder/bus name uppercased so they read as stems.
    Plugin-free     Duplicate the session into a new tab with FX removed;
    clone           names, colours, items, folders and routing kept.

  Requires ReaImGui and the Shared Libraries package.  SWS optional.
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
  r.ShowMessageBox("Stem Print & Handoff needs the 'Shared Libraries' package.\n\n" ..
    "Extensions > ReaPack > Browse packages > search 'Nathaniel Tools' > Shared Libraries > Install.\n" ..
    "(Or right-click the Nathaniel Tools repository > Install All.)", "Stem Print & Handoff", 0)
  return
end
do local ok, compat = pcall(require, "nt_imgui"); if ok then compat.install() end end
if not safe.require("Stem Print & Handoff", { imgui = true }) then return end

local APP = "Stem Print & Handoff"
local T = ui.tokens

--------------------------------------------------------------------------------
-- chunk helpers
--------------------------------------------------------------------------------
local function splitLines(c) local t = {} for l in (c .. "\n"):gmatch("(.-)\n") do t[#t + 1] = l end return t end
local function blockEnd(lines, s)
  local d = 0
  for i = s, #lines do
    local f = lines[i]:match("^%s*(.)")
    if f == "<" then d = d + 1 elseif f == ">" then d = d - 1 if d == 0 then return i end end
  end
end
-- Strip from a track chunk. what = { fx=bool, items=bool, envs=bool, receives=bool }
local function cleanChunk(chunk, what)
  local lines, out, i = splitLines(chunk), {}, 1
  while i <= #lines do
    local l = lines[i]
    if (what.items and l:match("^%s*<ITEM")) or (what.envs and l:match("^%s*<%u*ENV"))
       or (what.fx and l:match("^%s*<FXCHAIN")) then
      local e = blockEnd(lines, i); i = (e or i) + 1
    elseif what.receives and l:match("^%s*AUXRECV") then i = i + 1
    else out[#out + 1] = l; i = i + 1 end
  end
  local s = table.concat(out, "\n")
  s = s:gsub("TRACKID%s+{%x+%-%x+%-%x+%-%x+%-%x+}", "TRACKID " .. r.genGuid(""))
  return s
end

--------------------------------------------------------------------------------
-- track helpers
--------------------------------------------------------------------------------
local tName = safe.trackName
local function isFolderParent(t) return r.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH") == 1 end
local function activeProj() return r.EnumProjects(-1) end
local function projAlive(p) return safe.projAlive(p) end
local function trackAlive(p, t) return safe.trackAlive(p, t) end

local function insertTrackInto(proj, idx)
  if r.InsertTrackInProject then r.InsertTrackInProject(proj, idx, 0)
  else
    local cur = activeProj(); r.SelectProjectInstance(proj); r.InsertTrackAtIndex(idx, false); r.SelectProjectInstance(cur)
  end
  return r.GetTrack(proj, idx)
end

--------------------------------------------------------------------------------
-- state save / restore around a render  (keyed on GUID, never pointer)
--------------------------------------------------------------------------------
local function saveTrackState(t)
  return {
    guid  = r.GetTrackGUID(t),
    vol   = r.GetMediaTrackInfo_Value(t, "D_VOL"),
    pan   = r.GetMediaTrackInfo_Value(t, "D_PAN"),
    width = r.GetMediaTrackInfo_Value(t, "D_WIDTH"),
    mute  = r.GetMediaTrackInfo_Value(t, "B_MUTE"),
    sel   = r.GetMediaTrackInfo_Value(t, "I_SELECTED"),
    solo  = r.GetMediaTrackInfo_Value(t, "I_SOLO"),
    chunk = select(2, r.GetTrackStateChunk(t, "", false)),  -- FX bypass state, exactly
  }
end
local function restoreTrackState(proj, s, map)
  local t = map and map[s.guid] or nil
  if not trackAlive(proj, t) then return false end
  r.SetMediaTrackInfo_Value(t, "D_VOL", s.vol)
  r.SetMediaTrackInfo_Value(t, "D_PAN", s.pan)
  r.SetMediaTrackInfo_Value(t, "D_WIDTH", s.width)
  r.SetMediaTrackInfo_Value(t, "B_MUTE", s.mute)
  r.SetMediaTrackInfo_Value(t, "I_SELECTED", s.sel)
  r.SetMediaTrackInfo_Value(t, "I_SOLO", s.solo)
  return true
end

local function bypassAllInserts(t)
  for i = 0, r.TrackFX_GetCount(t) - 1 do r.TrackFX_SetEnabled(t, i, false) end
end
-- mute every send leaving a track; returns the previous mute states so they can be put back
local function muteSends(t)
  local prev = {}
  for i = 0, r.GetTrackNumSends(t, 0) - 1 do
    prev[i] = r.GetTrackSendInfo_Value(t, 0, i, "B_MUTE")
    r.SetTrackSendInfo_Value(t, 0, i, "B_MUTE", 1)
  end
  return prev
end

--------------------------------------------------------------------------------
-- render config
--------------------------------------------------------------------------------
local function projSampleRate()
  local ov = r.GetSetProjectInfo(0, "PROJECT_SRATE_USE", 0, false)
  local sr = r.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
  if ov ~= 0 and sr ~= 0 then return math.floor(sr), "project" end
  -- project follows the audio device: ask REAPER what it is running at
  local dev = r.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
  if dev and dev ~= 0 then return math.floor(dev), "device" end
  return 0, "device"
end

-- Every render key we touch, snapshotted before and put back after.
local RENDER_NUM = { "RENDER_BOUNDSFLAG", "RENDER_SETTINGS", "RENDER_SRATE", "RENDER_CHANNELS",
                     "RENDER_TAILFLAG", "RENDER_TAILMS", "RENDER_ADDTOPROJ", "RENDER_DITHER" }
local RENDER_STR = { "RENDER_FILE", "RENDER_PATTERN" }
local function snapshotRenderCfg()
  local s = { nums = {}, strs = {} }
  for _, k in ipairs(RENDER_NUM) do s.nums[k] = r.GetSetProjectInfo(0, k, 0, false) end
  for _, k in ipairs(RENDER_STR) do s.strs[k] = select(2, r.GetSetProjectInfo_String(0, k, "", false)) end
  return s
end
local function restoreRenderCfg(s)
  for _, k in ipairs(RENDER_NUM) do r.GetSetProjectInfo(0, k, s.nums[k], true) end
  for _, k in ipairs(RENDER_STR) do r.GetSetProjectInfo_String(0, k, s.strs[k], true) end
end
-- stems of the SELECTED tracks, whole project, project sample rate, 1s tail
local function configureStemRender(dir, pattern, settings)
  r.GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", 1, true)        -- entire project
  r.GetSetProjectInfo(0, "RENDER_SETTINGS", settings, true)   -- 2 = stems only (no master file)
  r.GetSetProjectInfo(0, "RENDER_SRATE", 0, true)             -- project sample rate
  r.GetSetProjectInfo(0, "RENDER_CHANNELS", 2, true)
  r.GetSetProjectInfo(0, "RENDER_TAILFLAG", 2, true)          -- tail applies to entire-project bounds
  r.GetSetProjectInfo(0, "RENDER_TAILMS", 1000, true)
  r.GetSetProjectInfo(0, "RENDER_ADDTOPROJ", 0, true)         -- we build the mirror tab ourselves
  r.GetSetProjectInfo_String(0, "RENDER_FILE", dir, true)
  r.GetSetProjectInfo_String(0, "RENDER_PATTERN", pattern, true)
end

--------------------------------------------------------------------------------
-- files
--------------------------------------------------------------------------------
local function mkdir(path) if r.RecursiveCreateDirectory then r.RecursiveCreateDirectory(path, 0) end end
local function listWavs(dir)
  local set = {}
  local i = 0
  while true do
    local f = r.EnumerateFiles(dir, i)
    if not f then break end
    if f:lower():match("%.wav$") then set[f] = true end
    i = i + 1
  end
  return set
end
-- REAPER's own filename sanitising for $track is close to this
local function safeName(s) return (s:gsub('[/\\:*?"<>|]', "_")) end
local function reveal(path)
  if r.CF_ShellExecute then r.CF_ShellExecute(path)
  elseif r.GetOS():match("OSX") or r.GetOS():match("macOS") then os.execute('open "' .. path .. '"')
  else os.execute('start "" "' .. path .. '"') end
end

--------------------------------------------------------------------------------
-- state
--------------------------------------------------------------------------------
local ctx = r.ImGui_CreateContext(APP)
ui.fonts(ctx)

local rows = {}          -- { guid, name, folder, depth, level, sel }
local lastSig, lastSigT = nil, 0
local mode = "bus"   -- raw / bus / master / wet
local opts = { mirror = true, preFaderCenter = false, testOne = false }
local outDir = ""
local paint = {}
local lastPrinted = nil  -- { dir=, files={...} }

local function say(msg, level) ui.say(ctx, msg, level) end

local function rebuild()
  rows = {}
  local proj = activeProj()
  if not projAlive(proj) then return end
  local sel = {}
  for i = 0, r.CountSelectedTracks(proj) - 1 do
    local st = r.GetSelectedTrack(proj, i)
    if st then sel[r.GetTrackGUID(st)] = true end
  end
  local level = 0
  for i = 0, r.CountTracks(proj) - 1 do
    local t = r.GetTrack(proj, i)
    if t then
      local folder = isFolderParent(t)
      local g = r.GetTrackGUID(t)
      local depth = r.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH")
      rows[#rows + 1] = { guid = g, name = tName(t), folder = folder, depth = depth, level = level,
                          sel = (sel[g] == true) or folder,
                          colour = ui.fromNative(r.GetTrackColor(t)) }
      level = math.max(0, level + depth)
    end
  end
  lastSig = safe.projSignature(proj)
  if outDir == "" then
    local pp = ({ r.EnumProjects(-1) })[2] or ""
    local d = (pp:match("^(.*)[/\\][^/\\]+$")) or ""
    outDir = (d ~= "" and (d .. "/Stems") or (r.GetProjectPath("") .. "/Stems"))
  end
end
local function selectedRows()
  local s = {}
  for _, row in ipairs(rows) do if row.sel then s[#s + 1] = row end end
  return s
end

--------------------------------------------------------------------------------
-- actions
--------------------------------------------------------------------------------
local function doUppercaseBuses()
  local proj = activeProj()
  r.Undo_BeginBlock2(proj)
  local count = 0
  for i = 0, r.CountTracks(proj) - 1 do
    local t = r.GetTrack(proj, i)
    if isFolderParent(t) then
      local nm = tName(t)
      if nm ~= nm:upper() then r.GetSetMediaTrackInfo_String(t, "P_NAME", nm:upper(), true); count = count + 1 end
    end
  end
  r.Undo_EndBlock2(proj, "Uppercase bus names", -1)
  r.TrackList_AdjustWindows(false)
  say(count > 0 and ("Uppercased %d bus name(s)."):format(count) or "Every bus name was already uppercase.", "ok")
  rebuild()
end

local function doPluginFreeClone()
  local src = activeProj()
  local n = r.CountTracks(src)
  r.Main_OnCommand(40859, 0)  -- new project tab
  local dst = activeProj()
  r.Undo_BeginBlock2(dst); r.PreventUIRefresh(1)
  for i = 0, n - 1 do
    local st = r.GetTrack(src, i)
    local nt = insertTrackInto(dst, i)
    local ok, chunk = r.GetTrackStateChunk(st, "", false)
    if ok then r.SetTrackStateChunk(nt, cleanChunk(chunk, { fx = true }), false) end
  end
  safe.normaliseFolders(dst)
  r.PreventUIRefresh(-1); r.Undo_EndBlock2(dst, "Plugin-free clone", -1)
  r.TrackList_AdjustWindows(false); r.UpdateArrange()
  say(("Plugin-free clone: %d tracks in a new tab. Names, colours, items, folders and routing kept; every FX removed."):format(n), "ok")
end

-- Build the handoff tab: same names/colours/folders as the printed rows, no
-- plugins, each printed file placed on its track. Runs AFTER the render.
local function buildMirrorTab(src, targets, dir, fileFor)
  r.Main_OnCommand(40859, 0)
  local dst = activeProj()
  r.Undo_BeginBlock2(dst); r.PreventUIRefresh(1)
  local srcMap = safe.guidMap(src)
  local placed = 0
  for i, row in ipairs(targets) do
    local nt = insertTrackInto(dst, i - 1)
    r.GetSetMediaTrackInfo_String(nt, "P_NAME", row.name, true)
    local st = srcMap[row.guid]
    if st then
      r.SetMediaTrackInfo_Value(nt, "I_CUSTOMCOLOR", r.GetMediaTrackInfo_Value(st, "I_CUSTOMCOLOR"))
      -- carry the REAL fader/pan into the mirror so it plays back like your mix
      r.SetMediaTrackInfo_Value(nt, "D_VOL", r.GetMediaTrackInfo_Value(st, "D_VOL"))
      r.SetMediaTrackInfo_Value(nt, "D_PAN", r.GetMediaTrackInfo_Value(st, "D_PAN"))
    end
    local f = fileFor(row)
    if f then
      local path = dir .. "/" .. f
      local src_ = r.PCM_Source_CreateFromFile(path)
      if src_ then
        local it = r.AddMediaItemToTrack(nt)
        local tk = r.AddTakeToMediaItem(it)
        r.SetMediaItemTake_Source(tk, src_)
        r.SetMediaItemInfo_Value(it, "D_POSITION", 0)
        r.SetMediaItemInfo_Value(it, "D_LENGTH", r.GetMediaSourceLength(src_))
        r.GetSetMediaItemTakeInfo_String(tk, "P_NAME", f, true)
        placed = placed + 1
      end
    end
  end
  safe.normaliseFolders(dst)
  r.PreventUIRefresh(-1); r.Undo_EndBlock2(dst, "Stem handoff tab", -1)
  r.TrackList_AdjustWindows(false); r.UpdateArrange()
  return placed
end

-- The print. One native stem pass for raw / bus / master; one isolated
-- pass per stem for fully wet. Everything touched is restored, even on error.
local function printStems()
  local proj = activeProj()
  local targets = selectedRows()
  if #targets == 0 then say("Tick at least one track or bus first.", "warn"); return false end
  if opts.testOne then targets = { targets[1] } end

  local saved = {}
  for i = 0, r.CountTracks(proj) - 1 do
    local t = r.GetTrack(proj, i)
    if t then saved[#saved + 1] = saveTrackState(t) end
  end
  local rcfg = snapshotRenderCfg()
  local before = listWavs(outDir)
  local sendMutes = {} -- guid -> { sendIndex -> previous B_MUTE }

  local function restoreAll()
    local missed = 0
    if projAlive(proj) then
      local map = safe.guidMap(proj)
      for _, s in ipairs(saved) do if not restoreTrackState(proj, s, map) then missed = missed + 1 end end
      if mode == "raw" then
        for _, s in ipairs(saved) do
          local t = map[s.guid]
          if trackAlive(proj, t) and s.chunk then r.SetTrackStateChunk(t, s.chunk, false) end
        end
      end
      for guid, prev in pairs(sendMutes) do
        local t = map[guid]
        if trackAlive(proj, t) then
          for i, v in pairs(prev) do r.SetTrackSendInfo_Value(t, 0, i, "B_MUTE", v) end
        end
      end
    else
      missed = #saved
    end
    restoreRenderCfg(rcfg)
    return missed
  end

  local fileOf = {}   -- guid -> filename we expect
  r.Undo_BeginBlock2(proj); r.PreventUIRefresh(1)
  local ok, err = pcall(function()
    local map = safe.guidMap(proj)
    mkdir(outDir)
    for i = 0, r.CountTracks(proj) - 1 do
      local t = r.GetTrack(proj, i)
      if t then r.SetMediaTrackInfo_Value(t, "I_SELECTED", 0) end
    end
    if mode == "wet" then
      -- isolated pass per stem: solo-in-place the track, print the MASTER mix
      for _, row in ipairs(targets) do
        local t = map[row.guid]
        if t and trackAlive(proj, t) then
          for j = 0, r.CountTracks(proj) - 1 do
            local o = r.GetTrack(proj, j); if o then r.SetMediaTrackInfo_Value(o, "I_SOLO", 0) end
          end
          r.SetMediaTrackInfo_Value(t, "I_SOLO", 2)   -- solo in place: sends and returns stay audible
          if opts.preFaderCenter then
            r.SetMediaTrackInfo_Value(t, "D_VOL", 1); r.SetMediaTrackInfo_Value(t, "D_PAN", 0)
          end
          local fname = safeName(row.name) .. " (wet)"
          fileOf[row.guid] = fname .. ".wav"
          configureStemRender(outDir, fname, 0)        -- 0 = master mix
          say(("Printing wet stem: %s"):format(row.name), "info")
          r.Main_OnCommand(42230, 0)                    -- render with these settings, auto-close
        end
      end
    else
      for _, row in ipairs(targets) do
        local t = map[row.guid]
        if t and trackAlive(proj, t) then
          r.SetMediaTrackInfo_Value(t, "I_SELECTED", 1)
          if opts.preFaderCenter then
            r.SetMediaTrackInfo_Value(t, "D_VOL", 1)
            r.SetMediaTrackInfo_Value(t, "D_PAN", 0)
            r.SetMediaTrackInfo_Value(t, "D_WIDTH", 1)
          end
          if mode == "raw" then bypassAllInserts(t) end
          if mode == "bus" then sendMutes[row.guid] = muteSends(t) end
          fileOf[row.guid] = safeName(row.name) .. ".wav"
        end
      end
      -- 2 = stems of the selected tracks (post-fader/pan, no master);
      -- 128 = selected tracks via master (each alone, through the master chain)
      configureStemRender(outDir, "$track", mode == "master" and 128 or 2)
      say(("Printing %d stem(s) [%s] to %s ..."):format(#targets, MODE_NAME[mode] or mode, outDir), "info")
      r.Main_OnCommand(42230, 0)
    end
  end)
  local missed = restoreAll()
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock2(proj, "Print stems (session restored)", -1)
  r.TrackList_AdjustWindows(false); r.UpdateArrange()

  -- what actually landed on disk
  local after = listWavs(outDir)
  local newFiles = {}
  for f in pairs(after) do if not before[f] then newFiles[#newFiles + 1] = f end end
  table.sort(newFiles)
  lastPrinted = { dir = outDir, files = newFiles }

  if ok then
    say(("Printed %d file(s) to %s. Faders, pans, mutes, FX bypass and render settings all put back."):format(#newFiles, outDir), "ok")
  else
    say("Print stopped: " .. tostring(err) .. "  Session fully restored, nothing left changed.", "danger")
  end
  if missed > 0 then
    say(("%d track(s) were deleted during the print, so their original volume/pan could not be put back."):format(missed), "warn")
  end
  if ok and opts.mirror and #newFiles > 0 then
    local function fileFor(row)
      local want = fileOf[row.guid]
      if want and after[want] then return want end
      -- REAPER may have sanitised differently: take the closest new file
      local base = safeName(row.name):lower()
      for _, f in ipairs(newFiles) do if f:lower():sub(1, #base) == base then return f end end
      return nil
    end
    local placed = buildMirrorTab(proj, targets, outDir, fileFor)
    say(("Handoff tab built in a new project tab: %d track(s), %d file(s) placed. Save that tab and send it."):format(#targets, placed), "ok")
  end
  rebuild()
  return ok
end

--------------------------------------------------------------------------------
-- frame
--------------------------------------------------------------------------------
local MODES = {
  { id = "raw",    label = "Raw",            tip = "No plugins at all. Fader and pan exactly as they are now. For someone who will mix from scratch." },
  { id = "bus",    label = "To the bus",     tip = "Plugins on, fader and pan as they are, every SEND muted - so no reverb or delay. What your bus hears from this track." },
  { id = "master", label = "Through master", tip = "Each stem on its own through the master bus and its plugins - your 'Stems Default' render preset." },
  { id = "wet",    label = "Fully wet",      tip = "Each stem solo-in-place INCLUDING its reverbs and delays. One pass per stem, so slower." },
}
local MODE_NAME = { raw = "Raw", bus = "To the bus", master = "Through master", wet = "Fully wet" }

local function frame()
  ui.header(ctx, APP, "clean stems out, session untouched", function() ui.dockToggle(ctx) end, 70)

  -- what to print
  ui.section(ctx, "How to print")
  mode = ui.segmented(ctx, "mode", MODES, mode)
  local ch, v
  ch, v = ui.toggle(ctx, "Unity fader, centre pan", opts.preFaderCenter,
    "OFF = stems at your current fader and pan (what you asked for). ON = every stem at 0 dB and centred so a mixer gets clean files; your real fader/pan is put back after and carried into the handoff tab.")
  if ch then opts.preFaderCenter = v end
  r.ImGui_SameLine(ctx, 0, 18)
  ch, v = ui.toggle(ctx, "Build a handoff tab", opts.mirror,
    "After printing, open a new project tab with the same names/colours/folders, no plugins, and each printed file already on its track.")
  if ch then opts.mirror = v end
  r.ImGui_SameLine(ctx, 0, 18)
  ch, v = ui.toggle(ctx, "Test: first stem only", opts.testOne, "Print just the first ticked stem so you can check the result before doing them all.")
  if ch then opts.testOne = v end
  local sr, srWhere = projSampleRate()
  ui.hint(ctx, sr > 0 and ("WAV at %d Hz (%s sample rate), your project's current bit depth."):format(sr, srWhere == "project" and "project's" or "audio device's")
                        or "WAV at the project's sample rate and current bit depth.")

  -- where
  ui.section(ctx, "Where the files go")
  r.ImGui_SetNextItemWidth(ctx, -170)
  local oc, ov = r.ImGui_InputText(ctx, "##dir", outDir); if oc then outDir = ov end
  ui.tip(ctx, "Folder for the printed WAVs. It is created if it does not exist.")
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "Choose...", { tip = "Pick the folder.", disabled = not r.JS_Dialog_BrowseForFolder }) then
    local rv, path = r.JS_Dialog_BrowseForFolder("Stems folder", outDir)
    if rv == 1 and path and path ~= "" then outDir = path end
  end
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "Reveal", { tip = "Open the folder in Finder / Explorer." }) then mkdir(outDir); reveal(outDir) end

  -- tracks & buses
  ui.section(ctx, "Tracks and buses to print")
  if ui.button(ctx, "All buses", { small = true, tip = "Tick every folder (bus) track." }) then for _, row in ipairs(rows) do row.sel = row.folder end end
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "All tracks", { small = true }) then for _, row in ipairs(rows) do row.sel = true end end
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "None", { small = true }) then for _, row in ipairs(rows) do row.sel = false end end
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "From REAPER selection", { small = true, tip = "Tick whatever is selected in the arrange window right now (plus every bus)." }) then rebuild() end
  r.ImGui_SameLine(ctx, 0, 16)
  local n = #selectedRows()
  ui.hint(ctx, ("%d of %d ticked"):format(n, #rows))

  if #rows == 0 then
    ui.empty(ctx, "No tracks in this project", "Add some tracks, or open the project you want to print from.")
  else
    if ui.tableBegin(ctx, "stems", { { name = "", w = 30 }, { name = "Track / bus" }, { name = "", w = 60 } }, { reserve = 96 }) then
      for i, row in ipairs(rows) do
        r.ImGui_TableNextRow(ctx); r.ImGui_PushID(ctx, i)
        r.ImGui_TableNextColumn(ctx)
        local c, val = ui.tick(ctx, "##s", row.sel, paint); if c then row.sel = val end
        r.ImGui_TableNextColumn(ctx)
        if row.level > 0 then r.ImGui_Dummy(ctx, 14 * row.level, 0); r.ImGui_SameLine(ctx, 0, 0) end
        if row.colour then
          local dl = r.ImGui_GetWindowDrawList(ctx)
          local x, y = r.ImGui_GetCursorScreenPos(ctx)
          r.ImGui_DrawList_AddRectFilled(dl, x, y + 3, x + 3, y + 15, row.colour, 1)
          r.ImGui_Dummy(ctx, 8, 0); r.ImGui_SameLine(ctx, 0, 0)
        end
        if row.folder then
          ui.pushFont(ctx, "body", true); r.ImGui_Text(ctx, row.name); ui.popFont(ctx)
        else r.ImGui_Text(ctx, row.name) end
        r.ImGui_TableNextColumn(ctx)
        if row.folder then ui.pill(ctx, "BUS", ui.accents.amber) end
        r.ImGui_PopID(ctx)
      end
      r.ImGui_EndTable(ctx)
    end
  end

  -- the big button + utilities
  local label = n == 1 and "PRINT 1 STEM" or ("PRINT %d STEMS"):format(n)
  if ui.button(ctx, label, { kind = "primary", w = 220, h = 34, disabled = n == 0,
      tip = "Renders now. Your session is saved and restored around it - one undo point." }) then
    ui.ask(ctx, "print")
  end
  r.ImGui_SameLine(ctx, 0, 14)
  if ui.button(ctx, "Uppercase bus names", { tip = "Every folder/bus name to UPPERCASE so stems read clearly." }) then doUppercaseBuses() end
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "Plugin-free clone tab", { tip = "Copy this session into a new tab with every FX removed. Names, colours, items, folders and routing kept." }) then
    doPluginFreeClone()
  end
  if lastPrinted and #lastPrinted.files > 0 then
    r.ImGui_SameLine(ctx)
    if ui.button(ctx, "Open printed folder", { kind = "ghost", tip = lastPrinted.dir }) then reveal(lastPrinted.dir) end
  end

  if ui.confirm(ctx, "print", {
      title = ("Print %d stem%s now?"):format(n, n == 1 and "" or "s"),
      text  = ("Mode: %s. Files go to %s. REAPER renders with its own progress window; the session is put back exactly afterwards."):format(MODE_NAME[mode] or mode, outDir),
      ok = "Print" }) then
    printStems()
  end

  ui.status(ctx, { idle = "Tick tracks or buses, choose a mode, press Print." })
end

--------------------------------------------------------------------------------
-- loop
--------------------------------------------------------------------------------
rebuild()
local function loop()
  local p = activeProj()
  if not projAlive(p) then rows = {}
  else
    local now = r.time_precise()
    if now - lastSigT > 0.25 then
      lastSigT = now
      if safe.projSignature(p) ~= lastSig then rebuild() end
    end
  end
  local open = ui.window(ctx, { title = APP, accent = ui.accents.amber, w = 760, h = 640, minW = 560, minH = 420 }, frame)
  if open then r.defer(loop) end
end
r.defer(loop)
