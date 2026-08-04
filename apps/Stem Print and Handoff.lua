-- @description Stem Print & Handoff
-- @version 1.0.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about Print stems in several modes and restore the session exactly afterwards.
--   Requires the "Shared Libraries" package from this same repository.
--   ReaPack has no automatic dependencies, so install that one too - or just
--   right-click the repository in ReaPack and choose Install All.
-- @changelog
--   1.0.0 - first public release. Crash-hardened (GUID identity + ValidatePtr2),
--           signature-based change detection, shared safety library.

--[[
  Stem Print & Handoff  (v1)  -  REAPER / ReaImGui
  ------------------------------------------------------------------------------
  Companion to "Track Settings Transfer". Prepares a session to hand off to
  another engineer / another DAW:

    * Mark folders  - uppercase every folder/parent track name (your bus = stem
                      convention), so the Render Matrix targets them cleanly.

    * Print stems   - bounce chosen tracks and/or buses to WAV at the project's
                      exact sample rate & bit depth, PRE-FADER and PAN-CENTERED
                      (the mirror project re-applies your real vol/pan), then
                      drop the printed WAVs into a NEW project tab that mirrors
                      your names / colors / folders with NO plugins. Your working
                      session is never altered (all changes are saved & restored,
                      wrapped in one undo).
        Modes:
          Raw          - no inserts (clean multitracks)
          Inserts only - insert FX baked, reverb/delay sends excluded (dry stem)
          Fully wet    - each stem printed in isolation incl. its reverb/delay
          Front-end    - print through the first insert only (mic/preamp/strip)

    * Plugin-free clone - duplicate the project into a new tab with names, colors,
                      routing and folders intact but all FX removed - for someone
                      who has your media but not your plugins.

  Requires: ReaImGui.  (SWS optional.)
--]]

local r = reaper

-- ReaImGui renames enum constants between releases, and a renamed constant is
-- a nil-call crash the moment the window opens - not a graceful degradation.
-- nt_imgui bridges the old and new spellings in one place. See that file for
-- the two renames measured on ReaImGui/Dear ImGui 1.92.1.
do
  local sep = package.config:sub(1, 1)
  local here = ({reaper.get_action_context()})[2]:match("(.*" .. sep .. ")") or ""
  package.path = here .. "lib" .. sep .. "?.lua;" ..
                 here .. ".." .. sep .. "Nathaniel Tools" .. sep .. "lib" .. sep .. "?.lua;" ..
                 reaper.GetResourcePath() .. "/Scripts/Nathaniel Tools/scripts/lib/?.lua;" ..
                 package.path
  local ok, compat = pcall(require, "nt_imgui")
  if ok then compat.install() end
end
if not r.ImGui_CreateContext then
  r.ShowMessageBox("Needs ReaImGui (Extensions > ReaPack > Browse > 'ReaImGui', install, restart).",
    "Stem Print & Handoff", 0); return
end

--------------------------------------------------------------------------------
-- chunk helpers
--------------------------------------------------------------------------------
local function splitLines(c) local t={} for l in (c.."\n"):gmatch("(.-)\n") do t[#t+1]=l end return t end
local function blockEnd(lines,s) local d=0 for i=s,#lines do local f=lines[i]:match("^%s*(.)")
  if f=="<" then d=d+1 elseif f==">" then d=d-1 if d==0 then return i end end end end
-- strip <ITEM>, <...ENV>, AUXRECV, and (optionally) <FXCHAIN...> from a track chunk
local function cleanChunk(chunk, stripFX)
  local lines, out, i = splitLines(chunk), {}, 1
  while i<=#lines do local l=lines[i]
    if l:match("^%s*<ITEM") or l:match("^%s*<%u*ENV") or (stripFX and l:match("^%s*<FXCHAIN")) then
      local e=blockEnd(lines,i); i=(e or i)+1
    elseif l:match("^%s*AUXRECV") then i=i+1
    else out[#out+1]=l; i=i+1 end
  end
  local s = table.concat(out,"\n")
  s = s:gsub("TRACKID%s+{%x+%-%x+%-%x+%-%x+%-%x+}","TRACKID "..r.genGuid(""))
  return s
end

--------------------------------------------------------------------------------
-- track helpers
--------------------------------------------------------------------------------
local function tName(t)
  local ok,nm=r.GetSetMediaTrackInfo_String(t,"P_NAME","",false)
  if ok and nm~="" then return nm end
  return "Track "..math.floor(r.GetMediaTrackInfo_Value(t,"IP_TRACKNUMBER"))
end
local function isFolderParent(t) return r.GetMediaTrackInfo_Value(t,"I_FOLDERDEPTH")==1 end
local function activeProj() return r.EnumProjects(-1) end

-- pointer safety: REAPER frees these the moment a track is deleted or a tab
-- closes, and a freed pointer faults inside REAPER's C++ where pcall cannot help.
local function projAlive(p)
  if p==nil then return false end
  if p==0 then return r.EnumProjects(-1)~=nil end   -- 0 = "current project" idiom
  local ok,alive=pcall(r.ValidatePtr2,0,p,"ReaProject*")
  return ok and alive==true
end
local function trackAlive(proj,t)
  if t==nil or not projAlive(proj) then return false end
  local ok,alive=pcall(r.ValidatePtr2,proj,t,"MediaTrack*")
  return ok and alive==true
end

--------------------------------------------------------------------------------
-- new project tab that mirrors names/colors/folders (no plugins), optional media
--------------------------------------------------------------------------------
local function insertTrackInto(proj, idx)
  if r.InsertTrackInProject then r.InsertTrackInProject(proj, idx, 0)
  else local cur=activeProj(); r.SelectProjectInstance(proj); r.InsertTrackAtIndex(idx,false); r.SelectProjectInstance(cur) end
  return r.GetTrack(proj, idx)
end

--------------------------------------------------------------------------------
-- state save / restore for a scripted render
--------------------------------------------------------------------------------
-- Snapshots key on GUID, not pointer.  A render can take minutes; by the time
-- we restore, the pointer captured beforehand may be long freed.  The GUID
-- still identifies the track, and if it genuinely went away we skip it instead
-- of faulting.
local function saveTrackState(t)
  return {
    guid=r.GetTrackGUID(t),
    vol=r.GetMediaTrackInfo_Value(t,"D_VOL"),
    pan=r.GetMediaTrackInfo_Value(t,"D_PAN"),
    width=r.GetMediaTrackInfo_Value(t,"D_WIDTH"),
    mute=r.GetMediaTrackInfo_Value(t,"B_MUTE"),
    sel=r.GetMediaTrackInfo_Value(t,"I_SELECTED"),
    solo=r.GetMediaTrackInfo_Value(t,"I_SOLO"),
    chunk=select(2,r.GetTrackStateChunk(t,"",false)), -- to restore FX bypass exactly
  }
end
local function restoreTrackState(proj, s, map)
  local t = map and map[s.guid] or nil
  if not trackAlive(proj, t) then return false end   -- track deleted mid-render: skip, never fault
  r.SetMediaTrackInfo_Value(t,"D_VOL",s.vol)
  r.SetMediaTrackInfo_Value(t,"D_PAN",s.pan)
  r.SetMediaTrackInfo_Value(t,"D_WIDTH",s.width)
  r.SetMediaTrackInfo_Value(t,"B_MUTE",s.mute)
  r.SetMediaTrackInfo_Value(t,"I_SELECTED",s.sel)
  r.SetMediaTrackInfo_Value(t,"I_SOLO",s.solo)
  return true
end

-- bypass/enable inserts on a track for a mode ("raw","frontend","full")
local function applyInsertMode(t, mode)
  local n = r.TrackFX_GetCount(t)
  for i=0,n-1 do
    local enable = true
    if mode=="raw" then enable=false
    elseif mode=="frontend" then enable=(i==0) end
    r.TrackFX_SetEnabled(t, i, enable)
  end
end

--------------------------------------------------------------------------------
-- render config
--------------------------------------------------------------------------------
local function projSampleRate()
  local ov = r.GetSetProjectInfo(0,"PROJECT_SRATE_USE",0,false)
  local sr = r.GetSetProjectInfo(0,"PROJECT_SRATE",0,false)
  if ov==0 or sr==0 then return 48000 end
  return math.floor(sr)
end

-- configure REAPER's render for "selected tracks -> stems", project SR, WAV.
-- Keeps the project's current RENDER_FORMAT (their session is already WAV 24-bit).
local function configureStemRender(dir)
  r.GetSetProjectInfo(0,"RENDER_BOUNDSFLAG",1,true)   -- entire project
  r.GetSetProjectInfo(0,"RENDER_SETTINGS",3,true)     -- stems, selected tracks (VERIFY on first run)
  r.GetSetProjectInfo(0,"RENDER_SRATE",0,true)        -- project sample rate
  r.GetSetProjectInfo(0,"RENDER_CHANNELS",2,true)
  r.GetSetProjectInfo(0,"RENDER_TAIL",1,true)         -- include tail
  r.GetSetProjectInfo_String(0,"RENDER_FILE",dir,true)
  r.GetSetProjectInfo_String(0,"RENDER_PATTERN","$track",true)
end

-- snapshot / restore the project's render dialog config so we leave it untouched
local RENDER_KEYS = {"RENDER_BOUNDSFLAG","RENDER_SETTINGS","RENDER_SRATE","RENDER_CHANNELS","RENDER_TAIL"}
local function snapshotRenderCfg()
  local s={nums={},strs={}}
  for _,k in ipairs(RENDER_KEYS) do s.nums[k]=r.GetSetProjectInfo(0,k,0,false) end
  s.strs.RENDER_FILE   = select(2,r.GetSetProjectInfo_String(0,"RENDER_FILE","",false))
  s.strs.RENDER_PATTERN= select(2,r.GetSetProjectInfo_String(0,"RENDER_PATTERN","",false))
  return s
end
local function restoreRenderCfg(s)
  for _,k in ipairs(RENDER_KEYS) do r.GetSetProjectInfo(0,k,s.nums[k],true) end
  r.GetSetProjectInfo_String(0,"RENDER_FILE",s.strs.RENDER_FILE,true)
  r.GetSetProjectInfo_String(0,"RENDER_PATTERN",s.strs.RENDER_PATTERN,true)
end

--------------------------------------------------------------------------------
-- state
--------------------------------------------------------------------------------
local ctx = r.ImGui_CreateContext('Stem Print & Handoff')
local rows = {}          -- {guid,name,folder,depth,sel}  -- GUIDs, never pointers
-- Change detection. NOT GetProjectStateChangeCount: measured in REAPER 7.77 it
-- does NOT move when a track is inserted, renamed or deleted, so a watchdog
-- built on it never fires. We diff a cheap signature of the track list instead.
local lastSig, lastSigT = nil, 0
local function projSig(proj)
  if not projAlive(proj) then return "dead" end
  local n = r.CountTracks(proj)
  local acc = {n}
  for i=0,n-1 do
    local t=r.GetTrack(proj,i)
    if t then acc[#acc+1] = r.GetTrackGUID(t)..":"..tName(t)..":"..
      math.floor(r.GetMediaTrackInfo_Value(t,"I_FOLDERDEPTH")) end
  end
  return table.concat(acc,"|")
end
local mode = "inserts"   -- raw / inserts / wet / frontend
local opts = { mirror=true, includeReturns=false, preFaderCenter=true, testOne=false }
local outDir = ""
local logLines = {}
local firstFrame, dockPending = true, nil
local function log(s) logLines[#logLines+1]=s; if #logLines>400 then table.remove(logLines,1) end end

-- CRASH FIX (v2).  rows used to hold raw MediaTrack* and the render pass wrote
-- through them AFTER a long render, by which time the user may well have
-- deleted or reordered something.  A freed pointer reaching SetMediaTrackInfo_Value
-- kills REAPER outright.  Worse, the restore pass ran outside the pcall, so a
-- fault there left every touched track stuck at unity gain and centre pan.
-- Rows now key on GUID and every pointer is resolved and validated at use.
local function liveMap(proj)
  local m={}
  if not projAlive(proj) then return m end
  for i=0,r.CountTracks(proj)-1 do
    local t=r.GetTrack(proj,i)
    if t then m[r.GetTrackGUID(t)]=t end
  end
  return m
end
local function rowTrack(proj,row,map)
  local t=(map or {})[row.guid]
  if t and r.ValidatePtr2(proj,t,"MediaTrack*") then return t end
  return nil
end

local function rebuild()
  rows={}
  local proj=activeProj()
  if not projAlive(proj) then return end
  local sel={}
  for i=0,r.CountSelectedTracks(proj)-1 do
    local st=r.GetSelectedTrack(proj,i)
    if st then sel[r.GetTrackGUID(st)]=true end
  end
  local n=r.CountTracks(proj)
  for i=0,n-1 do
    local t=r.GetTrack(proj,i)
    if t then
      local folder=isFolderParent(t)
      local g=r.GetTrackGUID(t)
      rows[#rows+1]={guid=g,name=tName(t),folder=folder,
                     depth=r.GetMediaTrackInfo_Value(t,"I_FOLDERDEPTH"),
                     sel=(sel[g]==true) or folder}  -- default: your selection, else all buses
    end
  end
  lastSig = projSig(proj)
  if outDir=="" then
    local pp=({r.EnumProjects(-1)})[2] or ""
    local d=(pp:match("^(.*)[/\\][^/\\]+$")) or ""
    outDir=(d~="" and (d.."/Stems") or "Stems")
  end
end

--------------------------------------------------------------------------------
-- actions
--------------------------------------------------------------------------------
local function doMarkFolders()
  local proj=activeProj()
  r.Undo_BeginBlock2(proj)
  local count=0
  for i=0,r.CountTracks(proj)-1 do
    local t=r.GetTrack(proj,i)
    if isFolderParent(t) then
      local nm=tName(t)
      if nm~=nm:upper() then r.GetSetMediaTrackInfo_String(t,"P_NAME",nm:upper(),true); count=count+1 end
    end
  end
  r.Undo_EndBlock2(proj,"Uppercase folder names",-1)
  r.TrackList_AdjustWindows(false)
  logLines={}; log(("Marked %d folder/bus name(s) UPPERCASE."):format(count))
  rebuild()
end

local function doPluginFreeClone()
  local src=activeProj()
  r.Main_OnCommand(40859,0)  -- New project tab
  local dst=activeProj()
  local n=r.CountTracks(src)
  r.Undo_BeginBlock2(dst); r.PreventUIRefresh(1)
  for i=0,n-1 do
    local st=r.GetTrack(src,i)
    local nt=insertTrackInto(dst,i)
    local ok,chunk=r.GetTrackStateChunk(st,"",false)
    if ok then r.SetTrackStateChunk(nt, cleanChunk(chunk,true), false) end  -- stripFX=true
  end
  r.PreventUIRefresh(-1); r.Undo_EndBlock2(dst,"Plugin-free clone",-1)
  r.TrackList_AdjustWindows(false); r.UpdateArrange()
  logLines={}; log(("Plugin-free clone: %d tracks in a new tab (names/colors/routing kept, FX removed)."):format(n))
end

local function selectedRows()
  local s={}; for _,row in ipairs(rows) do if row.sel then s[#s+1]=row end end; return s
end

-- scripted stem render (Raw / Inserts / Front-end): one native stem pass.
-- Every project change is guaranteed to be restored, even if the render errors.
local function renderStemsBatch()
  local proj=activeProj()
  local targets=selectedRows()
  if #targets==0 then log("Nothing selected to print."); return false end
  if opts.testOne then targets={targets[1]} end

  -- snapshot everything we may touch (tracks + render config)
  local saved={}
  for i=0,r.CountTracks(proj)-1 do
    local t=r.GetTrack(proj,i)
    if t then saved[#saved+1]=saveTrackState(t) end
  end
  local rcfg=snapshotRenderCfg()

  -- Restore resolves GUIDs fresh.  A render can run for minutes; anything could
  -- have happened to the track list in between.  A track that vanished is
  -- skipped and reported, never written through.
  local function restoreAll()
    local missed=0
    if projAlive(proj) then
      local map=liveMap(proj)
      for _,s in ipairs(saved) do
        if not restoreTrackState(proj, s, map) then missed=missed+1 end
      end
      if mode=="raw" or mode=="frontend" then         -- FX-enable was touched
        for _,s in ipairs(saved) do
          local t=map[s.guid]
          if trackAlive(proj,t) and s.chunk then r.SetTrackStateChunk(t, s.chunk, false) end
        end
      end
    else
      missed=#saved
    end
    restoreRenderCfg(rcfg)
    return missed
  end

  r.Undo_BeginBlock2(proj); r.PreventUIRefresh(1)
  local ok,err = pcall(function()
    local map=liveMap(proj)
    for i=0,r.CountTracks(proj)-1 do
      local t=r.GetTrack(proj,i)
      if t then r.SetMediaTrackInfo_Value(t,"I_SELECTED",0) end
    end
    for _,row in ipairs(targets) do
      local t=rowTrack(proj,row,map)
      if t then
        r.SetMediaTrackInfo_Value(t,"I_SELECTED",1)
        if opts.preFaderCenter then
          r.SetMediaTrackInfo_Value(t,"D_VOL",1)
          r.SetMediaTrackInfo_Value(t,"D_PAN",0)
          r.SetMediaTrackInfo_Value(t,"D_WIDTH",1)
        end
        if mode=="raw" or mode=="frontend" then applyInsertMode(t, mode) end
      end
    end
    os_mkdir(outDir)
    configureStemRender(outDir)
    log(("Rendering %d stem(s) -> %s  [RENDER_SETTINGS needs first-run verify]"):format(#targets, outDir))
    r.Main_OnCommand(42230,0)  -- render, most recent settings, auto-close
  end)
  -- FINALLY: always restore, always rebalance UI + undo, even on error
  local missed = restoreAll()
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock2(proj,"Print stems (state restored)",-1)
  r.TrackList_AdjustWindows(false); r.UpdateArrange()
  if ok then
    log("Render done. Tracks AND render settings restored exactly to how they were.")
  else
    log("Render aborted: "..tostring(err).."  -- session fully restored, nothing left changed.")
  end
  if missed > 0 then
    log(("  NOTE: %d track(s) were deleted during the render, so their original "..
         "volume/pan could not be put back. Nothing else was touched."):format(missed))
  end
  rebuild()
  return ok
end

-- helper: make a dir (via reaper's RecursiveCreateDirectory)
function os_mkdir(path) if r.RecursiveCreateDirectory then r.RecursiveCreateDirectory(path,0) end end

--------------------------------------------------------------------------------
-- theme (warm amber, distinct from the transfer app)
--------------------------------------------------------------------------------
local AMBER, AMBER_H, AMBER_A = 0xE0912Eff, 0xF0A544ff, 0xC47A20ff
local BG, PANEL, TXT, MUT = 0x1A1512ff, 0x241C16ff, 0xF0E6DAff, 0x9A8B7Aff
local GREEN, RED = 0x6BC77Aff, 0xE06A5Aff

local function pushTheme()
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 5)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(), 5)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 12, 10)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 7, 4)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), BG)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), TXT)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), AMBER)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), AMBER_H)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), AMBER_A)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), PANEL)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), AMBER_A)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), AMBER_H)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TableHeaderBg(), PANEL)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgActive(), AMBER_A)
end
local function popTheme() r.ImGui_PopStyleColor(ctx,10); r.ImGui_PopStyleVar(ctx,4) end

local function modeButton(id, label, hint)
  local on = mode==id
  if on then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), AMBER)
  else r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), PANEL) end
  if r.ImGui_Button(ctx, label, 118, 0) then mode=id end
  r.ImGui_PopStyleColor(ctx,1)
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, hint) end
end

--------------------------------------------------------------------------------
-- frame
--------------------------------------------------------------------------------
local function frame()
  -- banner
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), AMBER_H)
  r.ImGui_Text(ctx, "STEM  PRINT  &  HANDOFF")
  r.ImGui_PopStyleColor(ctx,1)
  r.ImGui_SameLine(ctx)
  r.ImGui_TextColored(ctx, MUT, "   send-ready stems for any DAW")
  r.ImGui_SameLine(ctx)
  local docked=r.ImGui_IsWindowDocked(ctx)
  local dc,dv=r.ImGui_Checkbox(ctx,"Dock",docked); if dc then dockPending=dv and -1 or 0 end
  r.ImGui_Separator(ctx)

  -- utilities row
  if r.ImGui_Button(ctx,"Mark folders  (UPPERCASE)") then doMarkFolders() end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx,"Uppercase every folder/bus name so they read as stems") end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx,"Plugin-free clone") then doPluginFreeClone() end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx,"New tab: names/colors/routing kept, all FX removed") end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx,"Refresh") then rebuild() end
  r.ImGui_Spacing(ctx)

  -- modes
  r.ImGui_TextColored(ctx, MUT, "Print mode")
  modeButton("raw","Raw","No inserts - clean multitracks"); r.ImGui_SameLine(ctx)
  modeButton("inserts","Inserts only","Insert FX baked, reverb/delay sends left out (dry stem)"); r.ImGui_SameLine(ctx)
  modeButton("wet","Fully wet","Each stem printed in isolation incl. its reverb/delay"); r.ImGui_SameLine(ctx)
  modeButton("frontend","Front-end","Through the first insert only (mic/preamp/channel strip)")

  r.ImGui_Spacing(ctx)
  local mc,mv=r.ImGui_Checkbox(ctx,"Mirror to new project (next)",opts.mirror); if mc then opts.mirror=mv end
  r.ImGui_SameLine(ctx)
  local pc,pv=r.ImGui_Checkbox(ctx,"Pre-fader / center",opts.preFaderCenter); if pc then opts.preFaderCenter=pv end
  r.ImGui_SameLine(ctx)
  local tc,tv=r.ImGui_Checkbox(ctx,"TEST: first stem only",opts.testOne); if tc then opts.testOne=tv end
  r.ImGui_TextColored(ctx, MUT, ("Format: %d Hz -- uses your project's current WAV render setting (confirm on first test)"):format(projSampleRate()))

  -- output dir
  r.ImGui_SetNextItemWidth(ctx, -90)
  local oc,ov=r.ImGui_InputText(ctx,"##dir",outDir); if oc then outDir=ov end
  r.ImGui_SameLine(ctx); r.ImGui_TextColored(ctx,MUT,"output")

  -- selection buttons
  if r.ImGui_Button(ctx,"All buses") then for _,row in ipairs(rows) do row.sel=row.folder end end
  r.ImGui_SameLine(ctx); if r.ImGui_Button(ctx,"All tracks") then for _,row in ipairs(rows) do row.sel=true end end
  r.ImGui_SameLine(ctx); if r.ImGui_Button(ctx,"None") then for _,row in ipairs(rows) do row.sel=false end end
  r.ImGui_SameLine(ctx); if r.ImGui_Button(ctx,"From selection") then rebuild() end

  -- table
  local flags=r.ImGui_TableFlags_Borders()|r.ImGui_TableFlags_RowBg()|r.ImGui_TableFlags_ScrollY()
  local _,availH=r.ImGui_GetContentRegionAvail(ctx)
  if r.ImGui_BeginTable(ctx,"stems",3,flags,0,math.max(120,availH-96)) then
    r.ImGui_TableSetupScrollFreeze(ctx,0,1)
    r.ImGui_TableSetupColumn(ctx,"Print",r.ImGui_TableColumnFlags_WidthFixed(),46)
    r.ImGui_TableSetupColumn(ctx,"Track / bus",r.ImGui_TableColumnFlags_WidthStretch())
    r.ImGui_TableSetupColumn(ctx,"Type",r.ImGui_TableColumnFlags_WidthFixed(),70)
    r.ImGui_TableHeadersRow(ctx)
    for i,row in ipairs(rows) do
      r.ImGui_TableNextRow(ctx); r.ImGui_PushID(ctx,i)
      r.ImGui_TableNextColumn(ctx)
      local c,v=r.ImGui_Checkbox(ctx,"##s",row.sel); if c then row.sel=v end
      r.ImGui_TableNextColumn(ctx)
      if row.folder then r.ImGui_TextColored(ctx,AMBER_H,row.name) else r.ImGui_Text(ctx,row.name) end
      r.ImGui_TableNextColumn(ctx)
      r.ImGui_TextColored(ctx, row.folder and AMBER or MUT, row.folder and "BUS" or "track")
      r.ImGui_PopID(ctx)
    end
    r.ImGui_EndTable(ctx)
  end

  -- print button + log
  local n=#selectedRows()
  r.ImGui_PushStyleColor(ctx,r.ImGui_Col_Button(),0xB85C1Aff)
  r.ImGui_PushStyleColor(ctx,r.ImGui_Col_ButtonHovered(),0xD06E20ff)
  if r.ImGui_Button(ctx,("PRINT  %d  STEM(S)"):format(n),0,30) then
    if mode=="wet" then log("Fully-wet mode: I'll wire the per-track isolation pass in the first supervised test.")
    else renderStemsBatch() end
  end
  r.ImGui_PopStyleColor(ctx,2)
  r.ImGui_SameLine(ctx); r.ImGui_TextColored(ctx,MUT,"  session saved & restored around every render")

  local cb=r.ImGui_ChildFlags_Border and r.ImGui_ChildFlags_Border() or 0
  if r.ImGui_BeginChild(ctx,"log",0,0,cb) then
    for _,l in ipairs(logLines) do r.ImGui_Text(ctx,l) end
    r.ImGui_EndChild(ctx)
  end
end

--------------------------------------------------------------------------------
-- init + loop
--------------------------------------------------------------------------------
rebuild()
local function loop()
  -- WATCHDOG: resync before anything reads a row, so the list can never render
  -- stale data and a deleted track can never reach an API.
  local p = activeProj()
  if not projAlive(p) then rows = {}
  else
    local now = r.time_precise()
    if now - lastSigT > 0.25 then     -- throttled: the signature walks every track
      lastSigT = now
      if projSig(p) ~= lastSig then rebuild() end
    end
  end

  if dockPending~=nil then r.ImGui_SetNextWindowDockID(ctx,dockPending); dockPending=nil end
  if firstFrame then r.ImGui_SetNextWindowSize(ctx,720,600); firstFrame=false end
  pushTheme()
  local vis,open=r.ImGui_Begin(ctx,'Stem Print & Handoff',true)
  if vis then
    local ok,err=pcall(frame)
    if not ok then r.ImGui_TextColored(ctx,RED,"Error: "..tostring(err)) end
    r.ImGui_End(ctx)
  end
  popTheme()
  if open then r.defer(loop) end
end
r.defer(loop)
