-- @description NPH Folders & Flow
-- @version 1.0.0
-- @author Jason Zac
-- @link https://daw.nathanielschool.com
-- @donation https://daw.nathanielschool.com/donate
-- @about Fix, build, dissolve, move and isolate track folders. Repairs broken folder nesting.
-- @provides
--   [nomain] lib/nph_safe.lua
--   [nomain] lib/nph_hierarchy.lua
-- @changelog
--   1.0.0 - first public release. Crash-hardened (GUID identity + ValidatePtr2),
--           signature-based change detection, shared safety library.

--[[
  Folders & Flow        NPH suite  -  green (structure)
  ----------------------------------------------------------------------------
  The things REAPER makes hard and you keep needing:

    * take ONE track out of a folder without dragging
    * fix a track that got nested in the wrong place
    * promote / demote a track and everything under it
    * dissolve a folder without deleting anything
    * move a whole folder - children and all - up or down
    * isolate a folder so the rest of the session gets out of the way
    * build folders automatically from track names
    * repair a session whose folder maths has gone wrong

  WHY THIS IS SAFE

  Every operation edits nesting LEVELS, never REAPER's I_FOLDERDEPTH integers
  directly, and then regenerates all the depths from the levels.  The output is
  always well-formed by construction, so it is not possible for this app to leave
  a folder hanging open and swallow the rest of your session.  The maths lives in
  NPH/lib/nph_hierarchy.lua and is covered by the harness.

  _SWS_UNFOLDER and _SWS_MOVETRACKUP / _SWS_MOVETRACKDOWN do NOT exist on this
  install, which is why none of this leans on SWS.

  Your existing shortcuts are untouched:  F = _SWS_MAKEFOLDER,  ` = 1042 41665

  Pointer safety: rows key on track GUID, never on MediaTrack*.  See nph_safe.lua.

  Requires: ReaImGui.
--]]

local r = reaper

if not r.ImGui_CreateContext then
  r.ShowMessageBox(
    "Folders & Flow needs ReaImGui.\n\n" ..
    "Extensions > ReaPack > Browse packages > search 'ReaImGui' > install > restart REAPER.",
    "Folders & Flow", 0)
  return
end

-- load the shared spine
local SEP  = package.config:sub(1, 1)
local HERE = ({ reaper.get_action_context() })[2]:match("(.*" .. SEP .. ")")
package.path = HERE .. "lib" .. SEP .. "?.lua;" .. package.path
local okS, safe = pcall(require, "nph_safe")
local okH, H    = pcall(require, "nph_hierarchy")
if not okS or not okH then
  r.ShowMessageBox(
    "Folders & Flow could not load its shared library.\n\nExpected:\n  " ..
    HERE .. "lib/nph_safe.lua\n  " .. HERE .. "lib/nph_hierarchy.lua\n\n" ..
    tostring(not okS and safe or H),
    "Folders & Flow", 0)
  return
end

local function activeProj() return r.EnumProjects(-1) end

--------------------------------------------------------------------------------
-- state
--------------------------------------------------------------------------------
local ctx = r.ImGui_CreateContext('Folders & Flow')
local rows = {}            -- { guid, name, level, parent, idx }
local sel  = {}            -- [guid] = true
local logLines = {}
local firstFrame, dockPending = true, nil
local lastSig, lastSigT = nil, 0
local minGroup = 2
local paint = { active = false, val = false, anchor = nil }

local function log(s) logLines[#logLines+1] = s; if #logLines > 200 then table.remove(logLines, 1) end end

local function rebuild()
  local proj = activeProj()
  rows = {}
  if not safe.projAlive(proj) then return end
  local levels = H.readLevels(proj)
  for i = 0, r.CountTracks(proj) - 1 do
    local t = r.GetTrack(proj, i)
    if t then
      rows[#rows+1] = {
        guid   = r.GetTrackGUID(t),
        name   = safe.trackName(t),
        level  = levels[i+1] or 0,
        parent = H.isParent(levels, i+1),
        idx    = i + 1,
      }
    end
  end
  lastSig = safe.projSignature(proj)
end

-- Run an edit expressed on levels, inside one undo point.
local function edit(label, fn)
  local proj = activeProj()
  if not safe.projAlive(proj) then log("No project."); return end
  local levels = H.readLevels(proj)
  local ok, err = fn(levels, proj)
  if ok == false then log("- " .. tostring(err)); return end
  r.Undo_BeginBlock2(proj)
  r.PreventUIRefresh(1)
  local changed = H.writeLevels(proj, levels)
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock2(proj, "Folders & Flow: " .. label, -1)
  r.TrackList_AdjustWindows(false); r.UpdateArrange()
  log(("%s  (%d track%s re-nested)"):format(label, changed, changed == 1 and "" or "s"))
  rebuild()
end

local function selectedIdx()
  local out = {}
  for _, row in ipairs(rows) do if sel[row.guid] then out[#out+1] = row.idx end end
  table.sort(out)
  return out
end

local function contiguous(list)
  if #list < 2 then return false end
  for i = 2, #list do if list[i] ~= list[i-1] + 1 then return false end end
  return true
end

--------------------------------------------------------------------------------
-- theme  (green = structure)
--------------------------------------------------------------------------------
local G, GH, GA = 0x3FA95Eff, 0x54D07Aff, 0x2E7F46ff
local BG, PANEL, TXT, MUT = 0x0F1512ff, 0x18211Cff, 0xE8F2EAff, 0x7E9186ff
local AMBER, RED = 0xE8B23Aff, 0xE0455Aff

local function pushTheme()
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 5)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 12, 10)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 7, 4)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), BG)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), TXT)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), PANEL)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), GA)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), GH)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), G)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), GA)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgActive(), GA)
end
local function popTheme()
  r.ImGui_PopStyleColor(ctx, 8)
  r.ImGui_PopStyleVar(ctx, 3)
end

--------------------------------------------------------------------------------
-- UI
--------------------------------------------------------------------------------
local function frame()
  local proj = activeProj()

  -- toolbar
  if r.ImGui_Button(ctx, "Repair folder maths") then
    edit("repair", function(levels) return true end)   -- rewrite is itself the repair
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Regenerate every folder depth from the nesting you can see.\nFixes a session where a folder was left hanging open.")
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Show all tracks") then H.showAll(proj); log("All tracks visible again.") end
  r.ImGui_SameLine(ctx)
  local dchg, dval = r.ImGui_Checkbox(ctx, "Dock", r.ImGui_IsWindowDocked(ctx))
  if dchg then dockPending = dval and -1 or 0 end
  r.ImGui_SameLine(ctx)
  if r.ImGui_SmallButton(ctx, "Rescan") then rebuild() end

  r.ImGui_Separator(ctx)

  -- selection actions
  local idxs = selectedIdx()
  r.ImGui_TextColored(ctx, MUT, ("%d track(s) ticked"):format(#idxs))
  r.ImGui_SameLine(ctx)
  if r.ImGui_SmallButton(ctx, "All") then for _, row in ipairs(rows) do sel[row.guid] = true end end
  r.ImGui_SameLine(ctx)
  if r.ImGui_SmallButton(ctx, "None") then sel = {} end

  if r.ImGui_Button(ctx, "Make folder from ticked") then
    if not contiguous(idxs) then
      log("- pick two or more tracks that sit next to each other")
    else
      edit("make folder", function(levels) return H.makeFolder(levels, idxs[1], idxs[#idxs]) end)
    end
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "The first ticked track becomes the folder parent.\nThey must be next to each other.")
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Indent >") then
    edit("indent", function(levels)
      for i = #idxs, 1, -1 do H.demote(levels, idxs[i]) end
      return #idxs > 0 or false, "nothing ticked"
    end)
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "< Outdent") then
    edit("outdent", function(levels)
      for _, i in ipairs(idxs) do H.promote(levels, i) end
      return #idxs > 0 or false, "nothing ticked"
    end)
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Out of folder") then
    edit("remove from folder", function(levels)
      for _, i in ipairs(idxs) do H.toRoot(levels, i) end
      return #idxs > 0 or false, "nothing ticked"
    end)
  end

  -- auto-group
  r.ImGui_SetNextItemWidth(ctx, 60)
  local mc, mv = r.ImGui_InputInt(ctx, "##min", minGroup, 0)
  if mc then minGroup = math.max(2, mv) end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Auto-group by name") then
    local plan = H.autoGroupPlan(proj, minGroup)
    if #plan == 0 then
      log("- no runs of " .. minGroup .. "+ adjacent tracks share a first word")
    else
      edit("auto-group by name", function(levels)
        for i = #plan, 1, -1 do
          local p = plan[i]
          H.makeFolder(levels, p.from, p.to)
        end
        return true
      end)
      for _, p in ipairs(plan) do
        log(("   grouped %d tracks under '%s'"):format(p.count, p.token))
      end
    end
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Groups ADJACENT top-level tracks that share a first word.\nNever reorders your session.")
  end

  r.ImGui_Separator(ctx)

  -- the tree
  local flags = r.ImGui_TableFlags_Borders() | r.ImGui_TableFlags_RowBg() | r.ImGui_TableFlags_ScrollY()
  local _, availH = r.ImGui_GetContentRegionAvail(ctx)
  if r.ImGui_BeginTable(ctx, "tree", 4, flags, 0, math.max(140, availH - 110)) then
    r.ImGui_TableSetupScrollFreeze(ctx, 0, 1)
    r.ImGui_TableSetupColumn(ctx, "", r.ImGui_TableColumnFlags_WidthFixed(), 26)
    r.ImGui_TableSetupColumn(ctx, "#", r.ImGui_TableColumnFlags_WidthFixed(), 32)
    r.ImGui_TableSetupColumn(ctx, "Track", r.ImGui_TableColumnFlags_WidthStretch())
    r.ImGui_TableSetupColumn(ctx, "Move / isolate", r.ImGui_TableColumnFlags_WidthFixed(), 190)
    r.ImGui_TableHeadersRow(ctx)

    for i, row in ipairs(rows) do
      r.ImGui_TableNextRow(ctx); r.ImGui_PushID(ctx, i)

      -- tick, with contiguous drag-paint (the standing requirement)
      r.ImGui_TableNextColumn(ctx)
      local on = sel[row.guid] == true
      local c, v = r.ImGui_Checkbox(ctx, "##on", on)
      if c then
        sel[row.guid] = v or nil
        paint.active, paint.val, paint.anchor = true, v, i
      elseif paint.active and r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDown(ctx, 0) then
        -- drag across rows: every row between the anchor and here takes the anchor's value
        local a, b = paint.anchor, i
        if a > b then a, b = b, a end
        for k = a, b do
          local g = rows[k] and rows[k].guid
          if g then sel[g] = paint.val or nil end
        end
      end

      r.ImGui_TableNextColumn(ctx); r.ImGui_TextColored(ctx, MUT, tostring(row.idx))

      -- name, indented by nesting level
      r.ImGui_TableNextColumn(ctx)
      local pad = string.rep("      ", row.level)
      if row.parent then
        r.ImGui_TextColored(ctx, GH, pad .. "v  " .. row.name)
      else
        r.ImGui_Text(ctx, pad .. "     " .. row.name)
      end

      -- per-row actions
      r.ImGui_TableNextColumn(ctx)
      if r.ImGui_SmallButton(ctx, "^") then
        r.Undo_BeginBlock2(proj)
        local ok, err = H.moveSubtree(proj, row.idx, -1)
        r.Undo_EndBlock2(proj, "Folders & Flow: move up", -1)
        if ok == false then log("- " .. tostring(err)) else log("Moved '" .. row.name .. "' (and its children) up.") end
        rebuild()
      end
      r.ImGui_SameLine(ctx)
      if r.ImGui_SmallButton(ctx, "v") then
        r.Undo_BeginBlock2(proj)
        local ok, err = H.moveSubtree(proj, row.idx, 1)
        r.Undo_EndBlock2(proj, "Folders & Flow: move down", -1)
        if ok == false then log("- " .. tostring(err)) else log("Moved '" .. row.name .. "' (and its children) down.") end
        rebuild()
      end
      r.ImGui_SameLine(ctx)
      if row.parent then
        if r.ImGui_SmallButton(ctx, "Dissolve") then
          edit("dissolve '" .. row.name .. "'", function(levels) return H.dissolve(levels, row.idx) end)
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_SmallButton(ctx, "Isolate") then
          H.isolate(proj, row.idx); log("Isolated '" .. row.name .. "'. Show all tracks to bring the rest back.")
        end
      else
        r.ImGui_TextColored(ctx, MUT, " -")
      end

      r.ImGui_PopID(ctx)
    end
    r.ImGui_EndTable(ctx)
  end

  if #logLines > 0 then
    r.ImGui_Separator(ctx)
    if r.ImGui_BeginChild(ctx, "log", 0, 76) then
      for _, l in ipairs(logLines) do
        r.ImGui_TextColored(ctx, l:sub(1,1) == "-" and AMBER or TXT, l)
      end
      r.ImGui_EndChild(ctx)
    end
  end
end

--------------------------------------------------------------------------------
-- init + loop
--------------------------------------------------------------------------------
rebuild()

local function loop()
  -- release the drag-paint when the mouse comes up anywhere
  if not r.ImGui_IsMouseDown(ctx, 0) then paint.active = false; paint.anchor = nil end

  -- watchdog.  NOT GetProjectStateChangeCount - measured in 7.77 it does not move
  -- on insert / rename / delete.  Signature diff, throttled.
  local proj = activeProj()
  if safe.projAlive(proj) then
    local now = r.time_precise()
    if now - lastSigT > 0.25 then
      lastSigT = now
      if safe.projSignature(proj) ~= lastSig then rebuild() end
    end
  else
    rows = {}
  end

  if dockPending ~= nil then r.ImGui_SetNextWindowDockID(ctx, dockPending); dockPending = nil end
  if firstFrame then r.ImGui_SetNextWindowSize(ctx, 860, 640); firstFrame = false end

  pushTheme()
  local vis, open = r.ImGui_Begin(ctx, 'Folders & Flow', true)
  if vis then
    local ok, err = pcall(frame)
    if not ok then r.ImGui_TextColored(ctx, RED, "Error: " .. tostring(err)) end
    r.ImGui_End(ctx)
  end
  popTheme()
  if open then r.defer(loop) end
end

r.defer(loop)
