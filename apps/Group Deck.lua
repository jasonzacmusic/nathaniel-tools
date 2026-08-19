-- @description Group Deck
-- @version 1.1.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about
--   Intelligent track grouping with buttons. Select tracks, tick what should
--   move together (solo, mute, record arm, volume, editing - pan off by default),
--   press GROUP. Every existing group is listed with its name, its members and
--   one tick per behaviour you can flip live; Select / Ungroup per group; and the
--   CLUTCH (REAPER's "all grouping enabled") as a big switch.
--   Requires the "Shared Libraries" package from this same repository
--   (right-click the repository in ReaPack > Install All).
-- @changelog
--   1.1.0 - unique auto names (ELECTRIC, ELECTRIC 2); grouped-edit scope switch (inside / start-or-end / start-and-end) with a fades hint.
--   1.0.0 - first version.

local r = reaper
do
  local sep = package.config:sub(1, 1)
  local here = ({ r.get_action_context() })[2]:match("(.*" .. sep .. ")") or ""
  package.path = here .. ".." .. sep .. "scripts" .. sep .. "lib" .. sep .. "?.lua;" ..
                 r.GetResourcePath() .. "/Scripts/Nathaniel Tools/scripts/lib/?.lua;" .. package.path
end
local okSafe, safe = pcall(require, "nt_safe")
local okUi,   ui   = pcall(require, "nt_ui")
if not (okSafe and okUi) then
  r.ShowMessageBox("Group Deck needs the 'Shared Libraries' package.\n\nExtensions > ReaPack > Browse packages > Nathaniel Tools > Shared Libraries > Install (or Install All).", "Group Deck", 0)
  return
end
do local ok, compat = pcall(require, "nt_imgui"); if ok then compat.install() end end
if not safe.require("Group Deck", { imgui = true }) then return end

local APP = "Group Deck"
local T = ui.tokens
local ctx = r.ImGui_CreateContext(APP)
ui.fonts(ctx)
local function say(m, l) ui.say(ctx, m, l) end

--------------------------------------------------------------------------------
-- behaviours  (REAPER group parameter names; lead + follow both set)
--------------------------------------------------------------------------------
local BEH = {
  { key = "vol",  label = "Volume",     names = { "VOLUME" },                 tip = "Faders move together." },
  { key = "pan",  label = "Pan",        names = { "PAN" },                    tip = "Pans move together. Usually OFF for a stereo pair or layered takes." },
  { key = "mute", label = "Mute",       names = { "MUTE" },                   tip = "Mute one, mute all." },
  { key = "solo", label = "Solo",       names = { "SOLO" },                   tip = "Solo one, solo all." },
  { key = "arm",  label = "Record arm", names = { "RECARM" },                 tip = "Arm one, arm all - one click arms the kit / the choir." },
  { key = "edit", label = "Editing",    names = { "MEDIA_EDIT", "RAZOR_EDIT" }, tip = "Split, trim, move, delete items together. Your clutch (Cmd+Shift+G) bypasses it." },
}
local want = { vol = true, pan = false, mute = true, solo = true, arm = true, edit = true }

local function member(t, name, suffix, hi)
  local fn = hi and r.GetSetTrackGroupMembershipHigh or r.GetSetTrackGroupMembership
  return fn(t, name .. suffix, 0, 0)
end
local function setMember(t, name, suffix, mask, value, hi)
  local fn = hi and r.GetSetTrackGroupMembershipHigh or r.GetSetTrackGroupMembership
  fn(t, name .. suffix, mask, value)
end
local function bitOf(g) if g <= 32 then return 1 << (g - 1), false else return 1 << (g - 33), true end end
local MAXG = r.GetSetTrackGroupMembershipHigh and 64 or 32

-- group name via project info (REAPER 6.72+), fallback ExtState
local function groupName(g)
  local ok, nm = r.GetSetProjectInfo_String(0, "TRACK_GROUP_NAME:" .. g, "", false)
  if ok and nm and nm ~= "" then return nm end
  return ""
end
local function setGroupName(g, nm) r.GetSetProjectInfo_String(0, "TRACK_GROUP_NAME:" .. g, nm, true) end

-- scan: groups -> { n=, name=, members={guid...}, flags={key=bool} }
local function scan()
  local groups = {}
  local n = r.CountTracks(0)
  for g = 1, MAXG do
    local bit, hi = bitOf(g)
    local members, flags, any = {}, {}, false
    for _, b in ipairs(BEH) do flags[b.key] = false end
    for i = 0, n - 1 do
      local t = r.GetTrack(0, i)
      local inG = false
      for _, b in ipairs(BEH) do
        for _, nm in ipairs(b.names) do
          local ok1, l = pcall(member, t, nm, "_LEAD", hi)
          local ok2, f = pcall(member, t, nm, "_FOLLOW", hi)
          if (ok1 and l & bit ~= 0) or (ok2 and f & bit ~= 0) then inG = true; flags[b.key] = true end
        end
      end
      if inG then members[#members + 1] = r.GetTrackGUID(t); any = true end
    end
    if any then groups[#groups + 1] = { n = g, name = groupName(g), members = members, flags = flags } end
  end
  return groups
end

local function firstFreeGroup(groups)
  local used = {}
  for _, gr in ipairs(groups) do used[gr.n] = true end
  for g = 1, MAXG do if not used[g] then return g end end
  return nil
end

-- name suggestion from what the tracks share (same idea as Instant Folder)
local function words(s) local o = {} for w in s:gmatch("%a+") do o[#o + 1] = w:lower() end return o end
local function suggestName(tracks)
  local names = {}
  for _, t in ipairs(tracks) do names[#names + 1] = safe.trackName(t) end
  if #names == 0 then return "GROUP" end
  local common = words(names[1])
  for i = 2, #names do
    local w = words(names[i]); local k = 0
    while k < #common and k < #w and common[k + 1] == w[k + 1] do k = k + 1 end
    for j = #common, k + 1, -1 do common[j] = nil end
  end
  local nm = #common > 0 and table.concat(common, " ") or (words(names[1])[1] or "group")
  nm = nm:gsub("%s+[lrcLRC]$", ""):gsub("%s+%d+$", "")
  nm = nm:upper()
  -- never two groups with the same name: ELECTRIC, ELECTRIC 2, ELECTRIC 3 ...
  local taken = {}
  for g = 1, MAXG do local gn = groupName(g); if gn ~= "" then taken[gn:upper()] = true end end
  if taken[nm] then local k = 2; while taken[nm .. " " .. k] do k = k + 1 end; nm = nm .. " " .. k end
  return nm
end

local function selectedTracks()
  local out = {}
  for i = 0, r.CountSelectedTracks(0) - 1 do out[#out + 1] = r.GetSelectedTrack(0, i) end
  return out
end

local function applyFlags(tracks, g, flags)
  local bit, hi = bitOf(g)
  for _, t in ipairs(tracks) do
    for _, b in ipairs(BEH) do
      for _, nm in ipairs(b.names) do
        pcall(setMember, t, nm, "_LEAD",   bit, flags[b.key] and bit or 0, hi)
        pcall(setMember, t, nm, "_FOLLOW", bit, flags[b.key] and bit or 0, hi)
      end
    end
  end
end
local function clearAllGroups(t)
  for g = 1, MAXG do
    local bit, hi = bitOf(g)
    for _, b in ipairs(BEH) do for _, nm in ipairs(b.names) do
      pcall(setMember, t, nm, "_LEAD", bit, 0, hi); pcall(setMember, t, nm, "_FOLLOW", bit, 0, hi)
    end end
  end
end

local CLUTCH = 40771  -- Track: Toggle all track grouping enabled
local function groupingOn() return r.GetToggleCommandState(CLUTCH) == 1 end

-- Which items on the OTHER tracks follow a grouped edit. REAPER has three rules,
-- each its own toggle action; find them by name so the ids never go stale.
local SCOPE = {
  { id = "enclosed", label = "inside the edited item",  name = "Options: Track media/razor edit grouping affects items that are enclosed by the edited item",
    tip = "Edit the LONGEST item and every item on the grouped tracks that sits inside its span follows. Best for layered takes of different lengths." },
  { id = "either",   label = "start OR end together",   name = "Options: Track media/razor edit grouping affects items that start or end at the same time",
    tip = "Items on the other tracks follow if they share the start or the end time with the edited item." },
  { id = "both",     label = "start AND end together",  name = "Options: Track media/razor edit grouping affects items that start and end at the same time",
    tip = "Strictest: only items with exactly the same start and end follow." },
}
for _, sc in ipairs(SCOPE) do
  for c = 40000, 43500 do if r.kbd_getTextFromCmd(c, 0) == sc.name then sc.cmd = c break end end
end
local function scopeNow()
  for _, sc in ipairs(SCOPE) do if sc.cmd and r.GetToggleCommandState(sc.cmd) == 1 then return sc.id end end
  return nil
end
local function setScope(id)
  for _, sc in ipairs(SCOPE) do if sc.id == id and sc.cmd and r.GetToggleCommandState(sc.cmd) ~= 1 then r.Main_OnCommand(sc.cmd, 0) end end
end

--------------------------------------------------------------------------------
-- actions
--------------------------------------------------------------------------------
local groups, lastScan = {}, 0
local nameEdit = ""

local function doGroup()
  local sel = selectedTracks()
  if #sel < 2 then say("Select two or more tracks first.", "warn") return end
  local g = firstFreeGroup(groups)
  if not g then say("All groups are in use - ungroup something first.", "warn") return end
  r.Undo_BeginBlock2(0)
  for _, t in ipairs(sel) do clearAllGroups(t) end      -- a track lives in one deck group at a time
  applyFlags(sel, g, want)
  local nm = nameEdit ~= "" and nameEdit or suggestName(sel)
  setGroupName(g, nm)
  if not groupingOn() then r.Main_OnCommand(CLUTCH, 0) end
  r.Undo_EndBlock2(0, "Group Deck: group " .. nm, -1)
  nameEdit = ""
  local on = {}
  for _, b in ipairs(BEH) do if want[b.key] then on[#on + 1] = b.label end end
  say(("%s: %d tracks grouped for %s."):format(nm, #sel, table.concat(on, ", ")), "ok")
  lastScan = 0
end

local function doUngroup(gr)
  r.Undo_BeginBlock2(0)
  local map = safe.guidMap(0)
  local bit, hi = bitOf(gr.n)
  for _, guid in ipairs(gr.members) do
    local t = map[guid]
    if t then for _, b in ipairs(BEH) do for _, nm in ipairs(b.names) do
      pcall(setMember, t, nm, "_LEAD", bit, 0, hi); pcall(setMember, t, nm, "_FOLLOW", bit, 0, hi)
    end end end
  end
  setGroupName(gr.n, "")
  r.Undo_EndBlock2(0, "Group Deck: ungroup " .. (gr.name ~= "" and gr.name or ("group " .. gr.n)), -1)
  say(("Ungrouped %s (%d tracks)."):format(gr.name ~= "" and gr.name or ("group " .. gr.n), #gr.members), "ok")
  lastScan = 0
end

local function doSelect(gr)
  local map = safe.guidMap(0)
  for i = 0, r.CountTracks(0) - 1 do r.SetTrackSelected(r.GetTrack(0, i), false) end
  local n = 0
  for _, guid in ipairs(gr.members) do local t = map[guid]; if t then r.SetTrackSelected(t, true); n = n + 1 end end
  r.TrackList_AdjustWindows(false)
  say(("Selected the %d tracks of %s."):format(n, gr.name ~= "" and gr.name or ("group " .. gr.n)), "info")
end

local function toggleFlag(gr, key, on)
  local map = safe.guidMap(0)
  local bit, hi = bitOf(gr.n)
  local tracks = {}
  for _, guid in ipairs(gr.members) do if map[guid] then tracks[#tracks + 1] = map[guid] end end
  r.Undo_BeginBlock2(0)
  for _, t in ipairs(tracks) do
    for _, b in ipairs(BEH) do if b.key == key then for _, nm in ipairs(b.names) do
      pcall(setMember, t, nm, "_LEAD", bit, on and bit or 0, hi); pcall(setMember, t, nm, "_FOLLOW", bit, on and bit or 0, hi)
    end end end
  end
  r.Undo_EndBlock2(0, "Group Deck: " .. key .. (on and " on" or " off"), -1)
  lastScan = 0
end

--------------------------------------------------------------------------------
-- frame
--------------------------------------------------------------------------------
local paintDummy = {}
local function frame()
  local now = r.time_precise()
  if now - lastScan > 0.5 then groups = scan(); lastScan = now end

  ui.header(ctx, APP, "what moves together", function() ui.dockToggle(ctx) end, 70)

  -- CLUTCH
  local on = groupingOn()
  if ui.button(ctx, on and "CLUTCH: GROUPS LIVE" or "CLUTCH: BYPASSED", { kind = "primary", colour = on and T.ok or T.danger, w = 220, h = 32,
      tip = "REAPER's 'all track grouping enabled'. Press to bypass every group for fine work, press again to re-engage. Same as Cmd+Shift+G." }) then
    r.Main_OnCommand(CLUTCH, 0)
    say(groupingOn() and "Groups live again." or "Groups bypassed - edits and faders move on their own until you press again.", groupingOn() and "ok" or "warn")
  end
  r.ImGui_SameLine(ctx, 0, 14)
  ui.hint(ctx, on and "Groups are active." or "Bypassed: nothing moves together right now.")
  -- grouped-edit scope
  r.ImGui_AlignTextToFramePadding(ctx); ui.hint(ctx, "Grouped edits follow items that are"); r.ImGui_SameLine(ctx, 0, 8)
  local items = {}
  for _, sc in ipairs(SCOPE) do if sc.cmd then items[#items + 1] = { id = sc.id, label = sc.label, tip = sc.tip } end end
  local cur = scopeNow()
  local nsc = ui.segmented(ctx, "scope", items, cur)
  if nsc ~= cur then setScope(nsc); say("Grouped edits now follow items that are " .. nsc:gsub("enclosed", "inside the edited item"):gsub("either", "starting or ending together"):gsub("both", "starting and ending together") .. ".", "ok") end
  r.ImGui_SameLine(ctx, 0, 10)
  ui.hint(ctx, "Fades: select the items across the tracks, then drag one fade - all selected fades move.")

  -- NEW GROUP
  ui.section(ctx, "New group from the selected tracks")
  local sel = selectedTracks()
  for i, b in ipairs(BEH) do
    if i > 1 then r.ImGui_SameLine(ctx, 0, 14) end
    local c, v = ui.toggle(ctx, b.label, want[b.key], b.tip)
    if c then want[b.key] = v end
  end
  r.ImGui_SetNextItemWidth(ctx, 200)
  local nc, nv = r.ImGui_InputTextWithHint(ctx, "##gname", sel[1] and ("name (auto: " .. suggestName(sel) .. ")") or "name", nameEdit)
  if nc then nameEdit = nv end
  ui.tip(ctx, "Optional. Left empty, the group is named from what the tracks share (Electric L/R/C -> ELECTRIC).")
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, ("GROUP SELECTED (%d)"):format(#sel), { kind = "primary", w = 210, h = 32, disabled = #sel < 2,
      tip = "Put the selected tracks into a new group with the ticked behaviours. A track leaves any earlier Group Deck group first." }) then doGroup() end

  -- GROUPS
  ui.section(ctx, "Groups in this project")
  if #groups == 0 then
    ui.empty(ctx, "No groups yet", "Select two or more tracks above, tick what should move together, press GROUP.")
    ui.pushToBottom(ctx, 44)
  else
    local cols = { { name = "#", w = 32 }, { name = "Group" }, { name = "Tracks", w = 60 } }
    for _, b in ipairs(BEH) do cols[#cols + 1] = { name = b.label == "Record arm" and "Arm" or b.label, w = b.label == "Editing" and 64 or 58 } end
    cols[#cols + 1] = { name = "", w = 150 }
    if ui.tableBegin(ctx, "groups", cols, { reserve = 8 }) then
      for _, gr in ipairs(groups) do
        r.ImGui_TableNextRow(ctx); r.ImGui_PushID(ctx, gr.n)
        r.ImGui_TableNextColumn(ctx); ui.dim(ctx, tostring(gr.n))
        r.ImGui_TableNextColumn(ctx)
        ui.pushFont(ctx, "body", true); r.ImGui_Text(ctx, gr.name ~= "" and gr.name or ("Group " .. gr.n)); ui.popFont(ctx)
        r.ImGui_TableNextColumn(ctx); r.ImGui_Text(ctx, tostring(#gr.members))
        for _, b in ipairs(BEH) do
          r.ImGui_TableNextColumn(ctx)
          local c, v = r.ImGui_Checkbox(ctx, "##" .. b.key, gr.flags[b.key])
          ui.tip(ctx, b.tip)
          if c then toggleFlag(gr, b.key, v) end
        end
        r.ImGui_TableNextColumn(ctx)
        if ui.button(ctx, "Select", { small = true, tip = "Select these tracks in REAPER." }) then doSelect(gr) end
        r.ImGui_SameLine(ctx)
        if ui.button(ctx, "Ungroup", { small = true, kind = "danger", tip = "Dissolve this group. Tracks stay, nothing else changes." }) then doUngroup(gr) end
        r.ImGui_PopID(ctx)
      end
      r.ImGui_EndTable(ctx)
    end
  end
  ui.status(ctx, { idle = "Select tracks, tick behaviours, press GROUP. Clutch bypasses everything." })
end

local function loop()
  local open = ui.window(ctx, { title = APP, accent = ui.accents.green, w = 860, h = 560, minW = 640, minH = 360 }, frame)
  if open then r.defer(loop) end
end
r.defer(loop)
