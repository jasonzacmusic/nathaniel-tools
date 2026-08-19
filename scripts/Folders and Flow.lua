-- @description Folders & Flow
-- @version 2.0.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about Build, dissolve, move and isolate track folders without dragging.
--   Indent / outdent ticked tracks, take a track out of its folder, move a
--   whole folder up or down, auto-group tracks by name, and repair a session
--   whose folder nesting has gone wrong.
--   Requires the "Shared Libraries" package from this same repository
--   (right-click the repository in ReaPack > Install All).
-- @changelog
--   2.0.0 - new shared look (nt_ui): header, sections, one status line + log,
--           confirm dialog, system font, drag-paint ticks, empty state.
--           Indent / Outdent / Out of folder on several ticked tracks now move
--           each track ONE level (a ticked track inside a ticked folder used to
--           be moved twice). Up / Down on a folder no longer scrambles the
--           nesting of its neighbours (a folder whose last track closed an
--           outer folder took that closer with it) and no longer wipes your
--           track selection. Isolate remembers what it hid; "Show all tracks"
--           only brings those back, never tracks you hid yourself. Both are
--           undoable. Auto-group asks first and says how many folders it will
--           make. Every action reports what it did in the status line.
--   1.0.0 - first public release.

--[[
  Folders & Flow        Nathaniel Tools  -  green (structure)
  ----------------------------------------------------------------------------
  The things REAPER makes hard and you keep needing:

    * make a folder from the tracks you tick (first ticked = the parent)
    * indent / outdent a track and everything under it
    * take ONE track out of a folder without dragging
    * dissolve a folder without deleting anything
    * move a whole folder - children and all - up or down
    * isolate a folder so the rest of the session gets out of the way,
      then "Show all tracks" brings back exactly what was hidden
    * build folders automatically from track names (asks first)
    * repair a session whose folder maths has gone wrong

  WHY THIS IS SAFE

  Every operation edits nesting LEVELS, never REAPER's I_FOLDERDEPTH integers
  directly, and then regenerates all the depths from the levels.  The output is
  always well-formed by construction, so it is not possible for this app to leave
  a folder hanging open and swallow the rest of your session.  The maths lives in
  scripts/lib/nt_hierarchy.lua and is covered by tests/hierarchy_test.lua.

  Multi-track Indent / Outdent / Out of folder act on SELECTION ROOTS: a ticked
  track whose folder parent is also ticked is left alone, because moving the
  parent already moves it.  Up / Down plan the new nesting on levels BEFORE the
  tracks are reordered, then write it back, so neighbours are never corrupted.

  _SWS_UNFOLDER and _SWS_MOVETRACKUP / _SWS_MOVETRACKDOWN do NOT exist on this
  install, which is why none of this leans on SWS.

  Your existing shortcuts are untouched:  F = _SWS_MAKEFOLDER,  ` = 1042 41665

  Pointer safety: rows key on track GUID, never on MediaTrack*.  See nt_safe.lua.

  Requires: ReaImGui and the Shared Libraries package.
--]]

local r = reaper

--------------------------------------------------------------------------------
-- libraries
--------------------------------------------------------------------------------
do
  local sep = package.config:sub(1, 1)
  local here = ((({ r.get_action_context() })[2] or ""):match("(.*" .. sep .. ")")) or ""
  package.path = here .. "lib" .. sep .. "?.lua;" ..
                 r.GetResourcePath() .. "/Scripts/Nathaniel Tools/scripts/lib/?.lua;" ..
                 package.path
end
local okSafe, safe = pcall(require, "nt_safe")
local okUi,   ui   = pcall(require, "nt_ui")
local okH,    H    = pcall(require, "nt_hierarchy")
if not (okSafe and okUi and okH) then
  r.ShowMessageBox("Folders & Flow needs the 'Shared Libraries' package.\n\n" ..
    "Extensions > ReaPack > Browse packages > search 'Nathaniel Tools' > Shared Libraries > Install.\n" ..
    "(Or right-click the Nathaniel Tools repository > Install All.)", "Folders & Flow", 0)
  return
end
do local ok, compat = pcall(require, "nt_imgui"); if ok then compat.install() end end
if not safe.require("Folders & Flow", { imgui = true }) then return end

local APP = "Folders & Flow"
local T = ui.tokens

local function activeProj() return r.EnumProjects(-1) end

--------------------------------------------------------------------------------
-- state
--------------------------------------------------------------------------------
local ctx = r.ImGui_CreateContext(APP)
ui.fonts(ctx)

local rows = {}            -- { guid, name, level, parent, idx, colour }
local sel  = {}            -- [guid] = true
local lastSig, lastSigT = nil, 0
local minGroup = 2
local paint = {}
local pendingPlan = nil    -- auto-group plan waiting for the confirm dialog

-- Tracks that ISOLATE hid, by GUID. "Show all tracks" only ever un-hides
-- these, so a track you hid on purpose stays hidden. Mirrored to ExtState so
-- it survives closing and reopening this window in the same REAPER session.
local EXT_SECTION, EXT_KEY = "NT_FoldersFlow", "isolate_hidden"
local isolatedHidden = {}
do
  local saved = r.GetExtState(EXT_SECTION, EXT_KEY)
  if saved and saved ~= "" then
    for g in saved:gmatch("[^|]+") do isolatedHidden[g] = true end
  end
end
local function persistHidden()
  local list = {}
  for g in pairs(isolatedHidden) do list[#list + 1] = g end
  r.SetExtState(EXT_SECTION, EXT_KEY, table.concat(list, "|"), false)
end
local function countHidden()
  local n = 0
  for _ in pairs(isolatedHidden) do n = n + 1 end
  return n
end

local function say(msg, level) ui.say(ctx, msg, level) end
local function plural(n, one, many) return n == 1 and one or (many or (one .. "s")) end

local function rebuild()
  local proj = activeProj()
  rows = {}
  if not safe.projAlive(proj) then return end
  local levels = H.readLevels(proj)
  for i = 0, r.CountTracks(proj) - 1 do
    local t = r.GetTrack(proj, i)
    if t then
      rows[#rows + 1] = {
        guid   = r.GetTrackGUID(t),
        name   = safe.trackName(t),
        level  = levels[i + 1] or 0,
        parent = H.isParent(levels, i + 1),
        idx    = i + 1,
        colour = ui.fromNative(r.GetTrackColor(t)),
      }
    end
  end
  -- forget ticks on tracks that no longer exist
  local alive = {}
  for _, row in ipairs(rows) do alive[row.guid] = true end
  for g in pairs(sel) do if not alive[g] then sel[g] = nil end end
  lastSig = safe.projSignature(proj)
end

-- Run an edit expressed on levels, inside one undo point.
-- fn(levels, proj) returns ok, err.  Returns ok, err, changed.
local function edit(label, fn)
  local proj = activeProj()
  if not safe.projAlive(proj) then say("No project is open.", "warn"); return false end
  local levels = H.readLevels(proj)
  local ok, err = fn(levels, proj)
  if ok == false then
    local msg = tostring(err or "Nothing to do.")
    msg = msg:sub(1, 1):upper() .. msg:sub(2)
    if not msg:match("[%.!?]$") then msg = msg .. "." end
    say(msg, "warn"); return false, err
  end
  r.Undo_BeginBlock2(proj)
  r.PreventUIRefresh(1)
  local changed = H.writeLevels(proj, levels)
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock2(proj, "Folders & Flow: " .. label, -1)
  r.TrackList_AdjustWindows(false); r.UpdateArrange()
  rebuild()
  return true, nil, changed
end

local function selectedIdx()
  local out = {}
  for _, row in ipairs(rows) do if sel[row.guid] then out[#out + 1] = row.idx end end
  table.sort(out)
  return out
end

local function contiguous(list)
  if #list < 2 then return false end
  for i = 2, #list do if list[i] ~= list[i - 1] + 1 then return false end end
  return true
end

-- Indent / Outdent / Out of folder on the ticked tracks, roots only.
local function multi(label, verb, opFn, idxs)
  local moved, skipped, why = 0, 0, nil
  local ok = edit(label, function(levels)
    if #idxs == 0 then return false, "Nothing is ticked." end
    moved, skipped, why = opFn(levels, idxs)
    if moved == 0 then return false, why or ("Nothing could be " .. verb .. ".") end
    return true
  end)
  if ok then
    local msg = ("%d %s %s."):format(moved, plural(moved, "track"), verb)
    if skipped > 0 then
      msg = msg .. (" %d skipped: %s."):format(skipped, why or "could not move")
      say(msg, "warn")
    else
      say(msg, "ok")
    end
  end
end

--------------------------------------------------------------------------------
-- actions
--------------------------------------------------------------------------------
local function doMakeFolder(idxs)
  if #idxs < 2 then say("Tick two or more tracks that sit next to each other.", "warn"); return end
  if not contiguous(idxs) then say("The ticked tracks must sit next to each other - the first one becomes the folder.", "warn"); return end
  local parentName = rows[idxs[1]] and rows[idxs[1]].name or "?"
  local ok = edit("make folder", function(levels) return H.makeFolder(levels, idxs[1], idxs[#idxs]) end)
  if ok then
    say(("Made a folder: '%s' now holds %d %s."):format(parentName, #idxs - 1, plural(#idxs - 1, "track")), "ok")
  end
end

local function doMove(row, dir)
  local proj = activeProj()
  if not safe.projAlive(proj) then say("No project is open.", "warn"); return end
  r.Undo_BeginBlock2(proj)
  r.PreventUIRefresh(1)
  local ok, err = H.moveSubtree(proj, row.idx, dir)
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock2(proj, "Folders & Flow: move " .. (dir < 0 and "up" or "down"), -1)
  r.TrackList_AdjustWindows(false); r.UpdateArrange()
  rebuild()
  if ok == false then
    say(("'%s': %s."):format(row.name, tostring(err)), "warn")
  else
    say(("Moved '%s'%s %s."):format(row.name, row.parent and " and its children" or "", dir < 0 and "up" or "down"), "ok")
  end
end

local function doDissolve(row)
  local ok = edit("dissolve '" .. row.name .. "'", function(levels) return H.dissolve(levels, row.idx) end)
  if ok then say(("Dissolved '%s' - it is an ordinary track now and its children sit beside it. Nothing deleted."):format(row.name), "ok") end
end

local function doIsolate(row)
  local proj = activeProj()
  if not safe.projAlive(proj) then say("No project is open.", "warn"); return end
  r.Undo_BeginBlock2(proj)
  r.PreventUIRefresh(1)
  local hidden = H.isolate(proj, row.idx)
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock2(proj, "Folders & Flow: isolate '" .. row.name .. "'", -1)
  r.TrackList_AdjustWindows(false); r.UpdateArrange()
  for _, g in ipairs(hidden) do isolatedHidden[g] = true end
  persistHidden()
  local total = countHidden()
  say(("Isolated '%s' - hid %d %s (%d hidden in all). 'Show all tracks' brings them back."):format(
      row.name, #hidden, plural(#hidden, "track"), total), "ok")
end

local function doShowAll()
  local proj = activeProj()
  if not safe.projAlive(proj) then say("No project is open.", "warn"); return end
  if countHidden() == 0 then
    say("Nothing to show - this window has not isolated anything. Tracks you hid yourself are left as they are.", "info")
    return
  end
  -- which of the remembered tracks are in THIS project?
  local here = safe.guidMap(proj)
  local inThis, elsewhere = {}, 0
  for g in pairs(isolatedHidden) do
    if here[g] then inThis[g] = true else elsewhere = elsewhere + 1 end
  end
  if next(inThis) == nil then
    -- none here: are they in another open tab, or gone for good?
    local other = false
    for _, pr in ipairs(safe.openProjects()) do
      if pr.proj ~= proj then
        local m = safe.guidMap(pr.proj)
        for g in pairs(isolatedHidden) do if m[g] then other = true; break end end
      end
      if other then break end
    end
    if other then
      say("The tracks Isolate hid are in another project tab - switch to that tab and press Show all tracks there.", "info")
    else
      isolatedHidden = {}; persistHidden()
      say("The tracks Isolate hid are not in any open project any more - nothing to show.", "info")
    end
    return
  end
  r.Undo_BeginBlock2(proj)
  r.PreventUIRefresh(1)
  local shown = H.showGuids(proj, inThis)
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock2(proj, "Folders & Flow: show all tracks", -1)
  r.TrackList_AdjustWindows(false); r.UpdateArrange()
  for g in pairs(inThis) do isolatedHidden[g] = nil end
  persistHidden()
  local msg = ("Showed %d %s again."):format(shown, plural(shown, "track"))
  if elsewhere > 0 then msg = msg .. (" %d more belong to another project tab."):format(elsewhere) end
  say(msg, "ok")
end

local function doRepair()
  local ok, _, changed = edit("repair folder maths", function() return true end)   -- the rewrite IS the repair
  if ok then
    if (changed or 0) == 0 then say("Folder maths already correct - nothing to repair.", "ok")
    else say(("Repaired: %d %s re-nested so every folder closes where it should."):format(changed, plural(changed, "track")), "ok") end
  end
end

local function planSummary(plan)
  local parts = {}
  local shown = math.min(#plan, 6)
  for i = 1, shown do
    parts[#parts + 1] = ("%s (%d)"):format(plan[i].token:upper(), plan[i].count)
  end
  local s = table.concat(parts, ", ")
  if #plan > shown then s = s .. (", and %d more"):format(#plan - shown) end
  return s
end

-- Recomputes the plan at the moment of confirming, so tracks added or moved
-- while the dialog was open can never be grouped from stale numbers.
local function doAutoGroup()
  local proj = activeProj()
  if not safe.projAlive(proj) then say("No project is open.", "warn"); return end
  local plan = H.autoGroupPlan(proj, minGroup)
  if #plan == 0 then say("Nothing to group any more - the track names changed.", "info"); return end
  local ok = edit("auto-group by name", function(levels)
    for i = #plan, 1, -1 do H.makeFolder(levels, plan[i].from, plan[i].to) end
    return true
  end)
  if ok then say(("Made %d %s: %s."):format(#plan, plural(#plan, "folder"), planSummary(plan)), "ok") end
end

--------------------------------------------------------------------------------
-- UI
--------------------------------------------------------------------------------
local function drawRow(i, row)
  r.ImGui_TableNextRow(ctx); r.ImGui_PushID(ctx, i)

  -- tick, with drag-paint
  r.ImGui_TableNextColumn(ctx)
  local c, v = ui.tick(ctx, "##on", sel[row.guid] == true, paint)
  if c then sel[row.guid] = v or nil end

  -- number
  r.ImGui_TableNextColumn(ctx)
  r.ImGui_TextColored(ctx, T.muted, tostring(row.idx))

  -- name, indented by nesting level, colour bar, folder parents bold
  r.ImGui_TableNextColumn(ctx)
  if row.level > 0 then r.ImGui_Dummy(ctx, 14 * row.level, 0); r.ImGui_SameLine(ctx, 0, 0) end
  if row.colour then
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local x, y = r.ImGui_GetCursorScreenPos(ctx)
    r.ImGui_DrawList_AddRectFilled(dl, x, y + 3, x + 3, y + 15, row.colour, 1)
    r.ImGui_Dummy(ctx, 8, 0); r.ImGui_SameLine(ctx, 0, 0)
  end
  if row.parent then
    ui.pushFont(ctx, "body", true); r.ImGui_Text(ctx, row.name); ui.popFont(ctx)
  else
    r.ImGui_Text(ctx, row.name)
  end

  -- actions
  r.ImGui_TableNextColumn(ctx)
  if ui.button(ctx, "Up", { small = true, tip = "Move this track (and everything inside it) above the track or folder just above." }) then
    doMove(row, -1)
  end
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "Down", { small = true, tip = "Move this track (and everything inside it) below the track or folder just below." }) then
    doMove(row, 1)
  end
  if row.parent then
    r.ImGui_SameLine(ctx)
    if ui.button(ctx, "Dissolve", { small = true, tip = "Turn this folder back into an ordinary track. Its children move up to sit beside it. Nothing is deleted." }) then
      doDissolve(row)
    end
    r.ImGui_SameLine(ctx)
    if ui.button(ctx, "Isolate", { small = true, tip = "Hide every other track so only this folder is on screen. 'Show all tracks' brings them back." }) then
      doIsolate(row)
    end
  end

  r.ImGui_PopID(ctx)
end

local function frame()
  local proj = activeProj()
  ui.header(ctx, APP, "folders that behave", function() ui.dockToggle(ctx) end, 70)

  if #rows == 0 then
    ui.empty(ctx, "No tracks in this project", "Add some tracks, or open the session whose folders you want to tidy.")
    ui.status(ctx, { idle = "Waiting for a project with tracks." })
    return
  end

  -- ticked tracks
  local idxs = selectedIdx()
  local n = #idxs
  ui.section(ctx, "Ticked tracks")
  ui.hint(ctx, ("%d ticked"):format(n))
  r.ImGui_SameLine(ctx, 0, 12)
  if ui.button(ctx, "All", { small = true, tip = "Tick every track." }) then for _, row in ipairs(rows) do sel[row.guid] = true end end
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "None", { small = true, tip = "Untick everything." }) then sel = {} end

  if ui.button(ctx, "Make folder from ticked", { kind = "primary", w = 200, disabled = n < 2,
      tip = "The first ticked track becomes the folder; the rest go inside it. They must sit next to each other." }) then
    doMakeFolder(idxs)
  end
  r.ImGui_SameLine(ctx, 0, 14)
  if ui.button(ctx, "Indent >", { disabled = n == 0,
      tip = "Push the ticked tracks one level deeper, into the folder above them. A ticked track inside a ticked folder moves with the folder, not twice." }) then
    multi("indent", "indented", H.demoteMany, idxs)
  end
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "< Outdent", { disabled = n == 0,
      tip = "Pull the ticked tracks one level out of their folder (children come along)." }) then
    multi("outdent", "outdented", H.promoteMany, idxs)
  end
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "Out of folder", { disabled = n == 0,
      tip = "Take the ticked tracks all the way out to the top level (children come along)." }) then
    multi("remove from folder", "taken out of the folder", H.toRootMany, idxs)
  end

  -- auto-group
  ui.section(ctx, "Auto-group")
  ui.hint(ctx, "Groups top-level tracks that sit next to each other and share a first word - Kick In / Kick Out become one folder. Never reorders anything.")
  r.ImGui_AlignTextToFramePadding(ctx)
  ui.hint(ctx, "At least")
  r.ImGui_SameLine(ctx)
  r.ImGui_SetNextItemWidth(ctx, 64)
  local mc, mv = r.ImGui_InputInt(ctx, "##min", minGroup, 0)
  if mc then minGroup = math.max(2, mv) end
  ui.tip(ctx, "How many matching tracks in a row it takes to make a folder.")
  r.ImGui_SameLine(ctx)
  r.ImGui_AlignTextToFramePadding(ctx)
  ui.hint(ctx, "tracks in a row")
  r.ImGui_SameLine(ctx, 0, 14)
  if ui.button(ctx, "Auto-group by name", { tip = "Looks at the names first and asks before it changes anything." }) then
    if not safe.projAlive(proj) then say("No project is open.", "warn")
    else
      local plan = H.autoGroupPlan(proj, minGroup)
      if #plan == 0 then
        say(("No runs of %d or more neighbouring top-level tracks share a first word - nothing to group."):format(minGroup), "info")
      else
        pendingPlan = plan
        ui.ask(ctx, "autogroup")
      end
    end
  end

  -- the tree
  ui.section(ctx, "Tracks")
  if ui.tableBegin(ctx, "tree", {
        { name = "", w = 30 }, { name = "#", w = 34 }, { name = "Track" }, { name = "", w = 250 } },
      { reserve = 96 }) then
    for i, row in ipairs(rows) do drawRow(i, row) end
    r.ImGui_EndTable(ctx)
  end

  -- utilities under the table
  if ui.button(ctx, "Repair folder maths",
      { tip = "Fixes a session where a folder never closed and swallowed everything after it. Rewrites every folder depth from the nesting you can see." }) then
    doRepair()
  end
  r.ImGui_SameLine(ctx)
  local hiddenN = countHidden()
  if ui.button(ctx, hiddenN > 0 and ("Show all tracks (%d hidden)"):format(hiddenN) or "Show all tracks",
      { tip = "Bring back the tracks Isolate hid. Tracks you hid yourself are left alone." }) then
    doShowAll()
  end

  -- auto-group confirm
  if pendingPlan and ui.confirm(ctx, "autogroup", {
      title = ("Make %d %s from track names?"):format(#pendingPlan, plural(#pendingPlan, "folder")),
      text  = "Will make " .. #pendingPlan .. " " .. plural(#pendingPlan, "folder") .. ": " .. planSummary(pendingPlan) ..
              ". The first track of each run becomes the folder. Nothing is reordered or deleted, and it is one undo step.",
      ok = "Make folders" }) then
    pendingPlan = nil
    doAutoGroup()
  end

  ui.status(ctx, { idle = "Tick tracks and press a button, or use Up / Down / Dissolve / Isolate on a row." })
end

--------------------------------------------------------------------------------
-- loop
--------------------------------------------------------------------------------
rebuild()
local function loop()
  -- watchdog.  NOT GetProjectStateChangeCount - measured in 7.77 it does not move
  -- on insert / rename / delete.  Signature diff, throttled.
  local proj = activeProj()
  if not safe.projAlive(proj) then rows = {}
  else
    local now = r.time_precise()
    if now - lastSigT > 0.25 then
      lastSigT = now
      if safe.projSignature(proj) ~= lastSig then rebuild() end
    end
  end
  local open = ui.window(ctx, { title = APP, accent = ui.accents.green, w = 860, h = 640, minW = 620, minH = 420 }, frame)
  if open then r.defer(loop) end
end
r.defer(loop)
