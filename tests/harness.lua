--[[
  Nathaniel Tools install + verify harness  (the standing regression gate)
  ----------------------------------------------------------------------------
  Run this from the Actions window any time you change a script. It registers
  everything, compiles everything, proves the crash-safety guarantees against a
  scratch project in its OWN TAB, and writes PASS/FAIL to _nt_results.txt.
  It never touches the project you had open.
--]]

local r = reaper
-- BASE is wherever this repo sits: harness.lua lives in <BASE>/tests/, so the
-- suite runs from any clone on any machine with no path edits.
local BASE = (debug.getinfo(1, "S").source:sub(2)):match("(.*/)"):gsub("tests/$", "")
local OUT  = BASE .. "_nt_results.txt"

local lines, pass, fail = {}, 0, 0
local function w(s) lines[#lines+1] = s end
local function check(ok, label)
  if ok then pass = pass + 1; w("PASS  " .. label)
  else fail = fail + 1; w("FAIL  " .. label) end
  return ok
end
local function finish()
  w(""); w(("=== %d passed, %d failed ==="):format(pass, fail))
  local f = io.open(OUT, "w"); f:write(table.concat(lines, "\n") .. "\n"); f:close()
  r.ShowConsoleMsg(("Nathaniel Tools harness: %d passed, %d failed. See _nt_results.txt\n"):format(pass, fail))
end

w("=== Nathaniel Tools install + verify  " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===")
w("REAPER " .. tostring(r.GetAppVersion())); w("")

w("-- environment --")
check(r.ImGui_CreateContext ~= nil,            "ReaImGui present")
check(r.BR_GetMediaTrackSendInfo_Track ~= nil, "SWS present")
check(r.SNM_GetIntConfigVar ~= nil,            "SWS SNM config vars present")
check(r.ValidatePtr2 ~= nil,                   "ValidatePtr2 present")
check(r.InsertTrackInProject ~= nil,           "InsertTrackInProject present")
w("")

package.path = BASE .. "scripts/lib/?.lua;" .. package.path
package.loaded["nt_safe"] = nil
local okLib, safe = pcall(require, "nt_safe")
w("-- shared library --")
if not check(okLib, "nt_safe.lua loads") then w("  " .. tostring(safe)); finish(); return end
check(safe.projAlive(0) == true,    "projAlive(0) = the current project")
check(safe.projAlive(nil) == false, "projAlive(nil) is false, not an error")
check(safe.projSignature ~= nil,    "projSignature exported (the working change detector)")
w("")

w("-- registration --")
local SCRIPTS = {
  "scripts/Solo Focus.lua", "scripts/Record Arm Toggle.lua", "scripts/FX Float Toggle.lua",
  "scripts/FX Open Close All.lua", "scripts/Region Next.lua", "scripts/Region Prev.lua",
  "scripts/Marker at Bar.lua", "scripts/Tempo at Bar.lua", "scripts/MIDI Render.lua",
  "scripts/Flush Paste.lua", "scripts/Duplicate Track.lua", "scripts/Unsolo Unselect.lua",
  "scripts/MIDI Batch Export.lua", "scripts/Folders and Flow.lua",
  -- The three windowed apps live in apps/ in the repo. An earlier copy of this
  -- harness looked for them at the root, which is where they happened to sit on
  -- the machine it was written on - so on any other install it reported three
  -- missing files and nobody would have known the layout was the cause.
  "apps/Palette and Look.lua", "apps/Track Settings Transfer.lua",
  "apps/Stem Print and Handoff.lua",
}
local reg = {}
for _, rel in ipairs(SCRIPTS) do
  local path = BASE .. rel
  local fh = io.open(path, "r")
  if not fh then check(false, "missing file: " .. rel)
  else
    fh:close()
    local cmd = r.AddRemoveReaScript(true, 0, path, true)
    if cmd and cmd ~= 0 then
      local tok = r.ReverseNamedCommandLookup(cmd)
      reg[#reg+1] = { rel = rel, cmd = cmd, tok = tok and ("_"..tok) or "?" }
      check(true, ("registered  %-38s %s"):format(rel, tok and ("_"..tok) or "?"))
    else check(false, "could not register " .. rel) end
  end
end
w("")

w("-- compile --")
for _, rel in ipairs(SCRIPTS) do
  local fn, err = loadfile(BASE .. rel)
  check(fn ~= nil, "compiles: " .. rel)
  if not fn then w("      " .. tostring(err)) end
end
w("")

--------------------------------------------------------------------------------
-- crash safety, proven against a scratch project in its own tab
--------------------------------------------------------------------------------
w("-- crash safety (scratch tab) --")
local before = r.EnumProjects(-1)
r.Main_OnCommand(40859, 0)
local proj = r.EnumProjects(-1)
check(proj ~= before, "opened a scratch tab; your session untouched")

r.PreventUIRefresh(1)
for i, nm in ipairs({ "KICK", "Snare", "Bass Gtr", "Rhodes", "Lead Vox" }) do
  r.InsertTrackInProject(proj, i-1, 0)
  r.GetSetMediaTrackInfo_String(r.GetTrack(proj, i-1), "P_NAME", nm, true)
end
r.PreventUIRefresh(-1)
check(r.CountTracks(proj) == 5, "built 5 scratch tracks")

local snap = safe.snapshot(proj)
check(#snap == 5, "snapshot() returned 5 rows")
local doomed    = snap[2].guid
local doomedPtr = safe.resolve(proj, doomed)
check(doomedPtr ~= nil, "cached a pointer the way the old code used to")

-- the change detector must notice a delete (GetProjectStateChangeCount does NOT)
local sigBefore = safe.projSignature(proj)
r.DeleteTrack(r.GetTrack(proj, 1))
local sigAfter = safe.projSignature(proj)
check(sigAfter ~= sigBefore, "projSignature CHANGES on delete (the watchdog fires)")
check(r.GetProjectStateChangeCount(proj) ~= nil, "GetProjectStateChangeCount readable but NOT trusted")

-- every one of these would have faulted on a raw pointer
check(safe.trackAlive(proj, doomedPtr) == false, "trackAlive() sees the freed pointer as dead")
check(safe.resolve(proj, doomed) == nil,         "resolve() on a deleted GUID returns nil")
check(safe.getVal(proj, doomedPtr, "D_VOL", -99) == -99, "getVal() returns the default, no fault")
check(safe.setVal(proj, doomedPtr, "D_VOL", 1) == false, "setVal() refuses and reports it")
check(safe.getName(proj, doomedPtr) == "",       "getName() is empty, not a fault")
w("  (REAPER is still running - that is the point of this section)")

r.SetMediaTrackInfo_Value(r.GetTrack(proj, 0), "I_FOLDERDEPTH", 1)
local fixes = safe.normaliseFolders(proj)
check(fixes > 0, "normaliseFolders repaired an unclosed folder")
local depth = 0
for i = 0, r.CountTracks(proj)-1 do
  depth = depth + r.GetMediaTrackInfo_Value(r.GetTrack(proj, i), "I_FOLDERDEPTH")
end
check(depth == 0, "folder depths balance to zero")

r.Main_OnCommand(40860, 0)
check(r.EnumProjects(-1) == before, "returned to the exact tab you started on")
w("")


--------------------------------------------------------------------------------
-- folder hierarchy: build a broken folder in the scratch tab and repair it
--------------------------------------------------------------------------------
w("-- folders & flow --")
package.loaded["nt_hierarchy"] = nil
local okH, H = pcall(require, "nt_hierarchy")
check(okH, "nt_hierarchy.lua loads")
if okH then
  r.Main_OnCommand(40859, 0)
  local fp = r.EnumProjects(-1)
  r.PreventUIRefresh(1)
  for i, nm in ipairs({ "DRUMS", "Kick", "Snare", "BASS", "Bass DI" }) do
    r.InsertTrackInProject(fp, i-1, 0)
    r.GetSetMediaTrackInfo_String(r.GetTrack(fp, i-1), "P_NAME", nm, true)
  end
  -- deliberately leave a folder hanging open, the classic session-eating bug
  r.SetMediaTrackInfo_Value(r.GetTrack(fp,0), "I_FOLDERDEPTH", 1)
  r.SetMediaTrackInfo_Value(r.GetTrack(fp,4), "I_FOLDERDEPTH", 0)
  r.PreventUIRefresh(-1)

  local lv = H.readLevels(fp)
  check(#lv == 5, "readLevels saw 5 tracks")
  H.writeLevels(fp, lv)
  local sum = 0
  for i = 0, r.CountTracks(fp)-1 do
    sum = sum + r.GetMediaTrackInfo_Value(r.GetTrack(fp,i), "I_FOLDERDEPTH")
  end
  check(sum == 0, "writeLevels closed the hanging folder (depths sum to 0)")

  -- make DRUMS a folder over Kick+Snare, then dissolve it
  local lv2 = H.readLevels(fp)
  check(H.makeFolder(lv2, 1, 3) == true, "makeFolder over tracks 1-3")
  H.writeLevels(fp, lv2)
  local lv3 = H.readLevels(fp)
  check(H.isParent(lv3, 1) == true, "DRUMS is now a folder parent")
  check(#H.subtree(lv3, 1) == 3, "its subtree is 3 tracks")
  check(H.dissolve(lv3, 1) == true, "dissolve accepted")
  H.writeLevels(fp, lv3)
  local lv4 = H.readLevels(fp)
  check(H.isParent(lv4, 1) == false, "after dissolve DRUMS is an ordinary track")
  check(r.CountTracks(fp) == 5, "dissolve deleted nothing")

  local plan = H.autoGroupPlan(fp, 2)
  check(type(plan) == "table", "autoGroupPlan returns a plan")

  r.Main_OnCommand(40860, 0)
  check(r.EnumProjects(-1) == before, "folder tab closed, back where we started")
end
w("")

local rf = io.open(BASE .. "_register.txt", "w")
if rf then
  rf:write("Nathaniel Tools registration  " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
  rf:write("The _RS tokens are authoritative. The integers drift between sessions.\n\n")
  for _, e in ipairs(reg) do rf:write(("%-40s cmd %-8d %s\n"):format(e.rel, e.cmd, e.tok)) end
  rf:close()
  w("wrote _register.txt with " .. #reg .. " entries")
end

finish()
