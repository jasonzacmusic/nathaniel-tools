-- @description Horn Delivery (check, render stems + EFX, file into JZ Horns, quality check, copy to Dropbox)
-- @version 1.1.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about
--   Select the stems and busses you want to deliver, then run this once. It:
--   1. Checks that the selected tracks are exactly the ones with music on them (nothing audible left out,
--      nothing empty or muted selected) and that every track name is unique.
--   2. Makes "JZ Horns" in the project folder with Trumpet Stems, Trombone Stems, Submixes and
--      ALL Trumpets & Trombones.
--   3. Renders your selection as stems plus the full horn mix, with the EFX folder muted.
--   4. Renders only the EFX folder, unmuted.
--   5. Puts your selection, mutes and render settings back exactly as they were.
--   6. Files every WAV: trumpet tracks -> Trumpet Stems, trombone tracks -> Trombone Stems,
--      section busses -> Submixes; the TRUMPETS / TROMBONE busses, the full mix and the EFX -> ALL Trumpets & Trombones.
--   7. Quality check: a file for every track, nothing silent, nothing clipping, right length.
--      Report saved in JZ Horns.
--   8. Offers to copy the whole project folder into the Dropbox folder you paste, and opens it.
--   Never deletes anything: an older WAV with the same name moves to JZ Horns/Previous Renders,
--   and a Dropbox file that would be replaced is kept in "_Replaced by JZ copy".
--   Uses your own render format; does not touch the render queue.
-- @changelog
--   1.1.0 - top-level busses (TRUMPETS, TROMBONE) go in ALL Trumpets & Trombones (Jason's layout).
--   1.0.0 - first version.

local r = reaper
local TITLE = "Horn Delivery"
local CATS = { tpt = "Trumpet Stems", tbn = "Trombone Stems", sub = "Submixes", all = "ALL Trumpets & Trombones" }
local MIX_NAME = "ALL Trumpets & Trombones"

local proj, projFile = r.EnumProjects(-1)
if projFile == "" then r.MB("Save the project first, so I know where its folder is.", TITLE, 0) return end
local projDir = projFile:match("^(.*)/[^/]*$")
local projName = r.GetProjectName(proj, ""):gsub("%.[Rr][Pp][Pp]$", "")
local stamp = os.date("%Y-%m-%d %H.%M.%S")

-- test hook (Claude's own checks): answers every question with yes and logs the dialogs
local AUTO = r.GetExtState("NathanielTools", "HornDeliveryAuto")
local function MB(msg, title, kind)
  if AUTO == "" then return r.MB(msg, title, kind) end
  local f = io.open(AUTO .. ".log", "a"); if f then f:write("----\n" .. msg .. "\n"); f:close() end
  return (kind == 1) and 1 or 6
end
local function Inputs(title, n, cap, def)
  if AUTO == "" then return r.GetUserInputs(title, n, cap, def) end
  return true, r.GetExtState("NathanielTools", "HornDeliveryAutoDropbox")
end

---------------------------------------------------------------- helpers
local function name(tr) local _, n = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false) return n end
local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
local function isFolder(tr) return r.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") == 1 end
local function muted(tr) return r.GetMediaTrackInfo_Value(tr, "B_MUTE") == 1 end
local function parent(tr) return r.GetParentTrack(tr) end
local function idx(tr) return math.floor(r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")) end
local function label(tr) return string.format("#%d %s", idx(tr), name(tr) ~= "" and name(tr) or "(no name)") end
local function shq(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
local function isDir(p) return (r.ExecProcess("/bin/test -d " .. shq(p), 2000) or ""):match("^0") ~= nil end
local function db(v) if not v or v <= 0 then return -150 end return 20 * math.log(v, 10) end

local tracks = {}
for i = 0, r.CountTracks(proj) - 1 do tracks[#tracks + 1] = r.GetTrack(proj, i) end

local function mutedChain(tr)        -- muted itself or under a muted folder
  local t = tr
  while t do if muted(t) then return true end t = parent(t) end
  return false
end
local function under(tr, top)        -- tr is top or inside it
  local t = tr
  while t do if t == top then return true end t = parent(t) end
  return false
end
local function hasMusic(tr)          -- items on it, or on anything inside it
  if r.CountTrackMediaItems(tr) > 0 then return true end
  if not isFolder(tr) then return false end
  for _, t in ipairs(tracks) do if t ~= tr and under(t, tr) and r.CountTrackMediaItems(t) > 0 then return true end end
  return false
end

-- the EFX folder: a track named EFX (or FX / EFFECTS)
local efx
for _, t in ipairs(tracks) do
  local n = trim(name(t)):upper()
  if n == "EFX" or n == "FX" or n == "EFFECTS" then efx = t break end
end
if not efx then MB("I couldn't find a track called EFX.\nName your effects folder EFX and run me again.", TITLE, 0) return end

local sel = {}
for _, t in ipairs(tracks) do if r.IsTrackSelected(t) and not under(t, efx) then sel[#sel + 1] = t end end
if #sel == 0 then MB("Select the stems and busses you want to render first (not the EFX), then run me again.", TITLE, 0) return end
local isSel = {}; for _, t in ipairs(sel) do isSel[t] = true end

local function category(tr)
  if isFolder(tr) and not parent(tr) then return "all" end   -- TRUMPETS / TROMBONE busses sit with the full mix
  if isFolder(tr) then return "sub" end
  local t = tr
  while t do
    local n = name(t):lower()
    if n:find("trumpet") or n:find("tpt") then return "tpt" end
    if n:find("trombone") or n:find("bone") or n:find("tbn") then return "tbn" end
    t = parent(t)
  end
  return nil
end

---------------------------------------------------------------- 1. checks before rendering
local problems, warnings = {}, {}
local function P(s) problems[#problems + 1] = s end
local function W(s) warnings[#warnings + 1] = s end

-- names: every track, busses and stems alike
local seen = {}
for _, t in ipairs(tracks) do
  local n = trim(name(t))
  if n == "" then P(label(t) .. " has no name")
  else
    local k = n:lower()
    if seen[k] then P(string.format("Two tracks share the name \"%s\" (#%d and #%d)", n, idx(seen[k]), idx(t))) else seen[k] = t end
    if n:find("[/:\\]") then P(label(t) .. " has / : or \\ in its name (breaks the file name)") end
    if k == MIX_NAME:lower() then P(label(t) .. " is named like the full mix file") end
  end
end

-- selection = exactly the tracks with music
for _, t in ipairs(tracks) do
  if not under(t, efx) and not isFolder(t) and r.CountTrackMediaItems(t) > 0 and not mutedChain(t) and not isSel[t] then
    P(label(t) .. " has music but is not selected")
  end
end
for _, t in ipairs(sel) do
  if not hasMusic(t) then P(label(t) .. " is selected but has nothing on it")
  elseif mutedChain(t) then P(label(t) .. " is selected but muted (its file would be silent)") end
  if not category(t) then W(label(t) .. " is not under a trumpet or trombone folder; it goes in Submixes") end
  for f = 0, r.TrackFX_GetCount(t) - 1 do
    if r.TrackFX_GetOffline(t, f) then local _, fx = r.TrackFX_GetFXName(t, f, "") W(label(t) .. ": plug-in is offline: " .. fx) end
  end
end
if not hasMusic(efx) and r.TrackFX_GetCount(efx) == 0 then
  local any = false
  for _, t in ipairs(tracks) do if t ~= efx and under(t, efx) and r.TrackFX_GetCount(t) > 0 then any = true end end
  if not any then W("The EFX folder has no effects in it") end
end

local function list(t, max)
  local out = {}
  for i = 1, math.min(#t, max) do out[#out + 1] = "• " .. t[i] end
  if #t > max then out[#out + 1] = string.format("…and %d more", #t - max) end
  return table.concat(out, "\n")
end

local nStems, nBus = 0, 0
for _, t in ipairs(sel) do if isFolder(t) then nBus = nBus + 1 else nStems = nStems + 1 end end
local head = string.format("%s\n%d stems + %d busses selected, plus the full mix and the EFX.\n\n", projName, nStems, nBus)
if #problems > 0 then
  local msg = head .. "Fix these first:\n" .. list(problems, 18)
  if #warnings > 0 then msg = msg .. "\n\nAlso:\n" .. list(warnings, 8) end
  if MB(msg .. "\n\nRender anyway?", TITLE, 4) ~= 6 then return end
else
  local msg = head .. "Checks passed: every track with music is selected, all names are unique."
  if #warnings > 0 then msg = msg .. "\n\nWorth a look:\n" .. list(warnings, 8) end
  if MB(msg .. "\n\nRender now?", TITLE, 1) ~= 1 then return end
end

---------------------------------------------------------------- 2. folders
local horns = projDir .. "/JZ Horns"
for _, c in pairs(CATS) do r.RecursiveCreateDirectory(horns .. "/" .. c, 0) end
local stage = horns .. "/_Rendering " .. stamp
r.RecursiveCreateDirectory(stage .. "/stems", 0)
r.RecursiveCreateDirectory(stage .. "/efx", 0)

---------------------------------------------------------------- 3-5. render, then put everything back
local keepS = {}
for _, k in ipairs({ "RENDER_FILE", "RENDER_PATTERN" }) do local _, v = r.GetSetProjectInfo_String(proj, k, "", false) keepS[k] = v end
local keepN = {}
for _, k in ipairs({ "RENDER_SETTINGS", "RENDER_ADDTOPROJ" }) do keepN[k] = r.GetSetProjectInfo(proj, k, 0, false) end
local keepSel, keepMute = {}, {}
for _, t in ipairs(tracks) do keepSel[t] = r.IsTrackSelected(t); keepMute[t] = muted(t) end

local function selectOnly(list_)
  for _, t in ipairs(tracks) do r.SetTrackSelected(t, false) end
  for _, t in ipairs(list_) do r.SetTrackSelected(t, true) end
end
local function targets()
  local _, s = r.GetSetProjectInfo_String(proj, "RENDER_TARGETS", "", false)
  local out = {}
  for f in (s or ""):gmatch("[^;]+") do out[#out + 1] = f end
  return out
end
local function render(dir, settings)
  r.GetSetProjectInfo_String(proj, "RENDER_FILE", dir, true)
  r.GetSetProjectInfo_String(proj, "RENDER_PATTERN", "$track", true)
  r.GetSetProjectInfo(proj, "RENDER_SETTINGS", settings, true)
  r.GetSetProjectInfo(proj, "RENDER_ADDTOPROJ", 0, true)
  local t = targets()
  r.Main_OnCommand(42230, 0)   -- File: Render project, using the most recent render settings, auto-close render dialog
  return t
end

local stemTargets, efxTargets
local ok, err = pcall(function()
  r.PreventUIRefresh(1)
  -- pass 1: stems + full mix, EFX muted
  r.SetMediaTrackInfo_Value(efx, "B_MUTE", 1)
  selectOnly(sel)
  r.PreventUIRefresh(-1)
  stemTargets = render(stage .. "/stems", 1)     -- 1 = stems (selected tracks) + master mix
  -- pass 2: only the EFX, unmuted (and anything muted inside it unmuted for the pass)
  r.PreventUIRefresh(1)
  for _, t in ipairs(tracks) do if under(t, efx) then r.SetMediaTrackInfo_Value(t, "B_MUTE", 0) end end
  selectOnly({ efx })
  r.PreventUIRefresh(-1)
  efxTargets = render(stage .. "/efx", 3)        -- 3 = selected tracks only, no master mix
end)
-- always put it all back
r.PreventUIRefresh(1)
for _, t in ipairs(tracks) do
  if r.ValidatePtr2(proj, t, "MediaTrack*") then
    r.SetMediaTrackInfo_Value(t, "B_MUTE", keepMute[t] and 1 or 0)
    r.SetTrackSelected(t, keepSel[t])
  end
end
for k, v in pairs(keepS) do r.GetSetProjectInfo_String(proj, k, v, true) end
for k, v in pairs(keepN) do r.GetSetProjectInfo(proj, k, v, true) end
r.PreventUIRefresh(-1)
r.TrackList_AdjustWindows(false); r.UpdateArrange()
if not ok then MB("The render stopped: " .. tostring(err) .. "\nYour selection, mutes and render settings are back as they were.", TITLE, 0) return end

---------------------------------------------------------------- 6. file the WAVs
local function base(p) return p:match("([^/]+)$") end
local function stem(p) return (base(p):gsub("%.[^.]+$", "")) end
local function exists(p) return r.file_exists(p) end

local function place(src, cat, newName)
  local dstDir = horns .. "/" .. CATS[cat]
  local dst = dstDir .. "/" .. (newName or base(src))
  if exists(dst) then                                   -- never overwrite: the older file moves aside
    local old = horns .. "/Previous Renders/" .. stamp .. "/" .. CATS[cat]
    r.RecursiveCreateDirectory(old, 0)
    os.rename(dst, old .. "/" .. base(dst))
  end
  local okm = os.rename(src, dst)
  return okm and dst or nil
end

-- match each rendered file to its track by name (pattern is $track)
local byName = {}
for _, t in ipairs(sel) do byName[trim(name(t)):lower()] = t end
local filed, missing = {}, {}   -- filed[track or "mix"/"efx"] = path
for _, f in ipairs(stemTargets or {}) do
  local s = stem(f):lower()
  local t = byName[s]
  if exists(f) then
    if t then filed[t] = place(f, category(t) or "sub")
    else filed.mix = place(f, "all", MIX_NAME .. ".wav") end   -- the one file that is not a track is the full mix
  end
end
for _, f in ipairs(efxTargets or {}) do
  if exists(f) then filed.efx = place(f, "all", "EFX.wav") end
end
os.remove(stage .. "/stems"); os.remove(stage .. "/efx"); os.remove(stage)   -- only removes them if empty

---------------------------------------------------------------- 7. quality check
local projLen = r.GetProjectLength(proj)
local srate = r.GetSetProjectInfo(proj, "PROJECT_SRATE", 0, false)
if srate == 0 then srate = tonumber(select(2, r.GetAudioDeviceInfo("SRATE", ""))) or 0 end
local qc, rows = {}, {}
local function Q(s) qc[#qc + 1] = s end
local function inspect(path, what)
  local src = r.PCM_Source_CreateFromFile(path)
  if not src then Q(what .. ": file won't open") return end
  local len = r.GetMediaSourceLength(src)
  local sr = r.GetMediaSourceSampleRate(src)
  local g = r.CalculateNormalization(src, 2, 0, 0, 0)   -- gain to reach 0 dBFS peak
  r.PCM_Source_Destroy(src)
  local peak = (g and g > 0 and g < 1e12) and -db(g) or -150
  rows[#rows + 1] = string.format("%-44s peak %6.1f dB  %6.1f s", what, peak, len)
  if peak < -80 then Q(what .. " is silent") end
  if peak > -0.1 then Q(string.format("%s is clipping (peak %.1f dB)", what, peak)) end
  if len < projLen - 0.5 then Q(string.format("%s is shorter than the song (%.1f s of %.1f s)", what, len, projLen)) end
  if srate > 0 and math.abs(sr - srate) > 1 then Q(string.format("%s is %d Hz, project is %d Hz", what, sr, srate)) end
end
for _, t in ipairs(sel) do
  local what = (CATS[category(t) or "sub"]) .. "/" .. trim(name(t))
  if filed[t] then inspect(filed[t], what) else Q("No file for " .. label(t)); missing[#missing + 1] = t end
end
if filed.mix then inspect(filed.mix, CATS.all .. "/" .. MIX_NAME) else Q("The full mix file is missing") end
if filed.efx then inspect(filed.efx, CATS.all .. "/EFX") else Q("The EFX file is missing") end
for _, w in ipairs(warnings) do Q(w) end
for _, p in ipairs(problems) do Q("Rendered anyway: " .. p) end

local counts = {}
for _, c in pairs(CATS) do
  local n, i = 0, 0
  while r.EnumerateFiles(horns .. "/" .. c, i) do if r.EnumerateFiles(horns .. "/" .. c, i):lower():match("%.wav$") then n = n + 1 end i = i + 1 end
  counts[#counts + 1] = string.format("%s: %d", c, n)
end
table.sort(counts)

local report = {
  "Horn Delivery — " .. projName, os.date("%d %b %Y, %H:%M"), "",
  table.concat(counts, "\n"), "",
  (#qc == 0 and "Quality check: all clear." or ("Quality check — look at these:\n" .. list(qc, 200))), "",
  "Files:", table.concat(rows, "\n"),
}
local rp = horns .. "/Delivery Report " .. stamp .. ".txt"
local fh = io.open(rp, "w"); if fh then fh:write(table.concat(report, "\n") .. "\n"); fh:close() end

local summary = string.format("Rendered and filed in JZ Horns.\n%s\n\n%s",
  table.concat(counts, "\n"), #qc == 0 and "Quality check: all clear." or ("Look at these:\n" .. list(qc, 12)))

---------------------------------------------------------------- 8. copy to Dropbox
if MB(summary .. "\n\nCopy the whole project folder to Dropbox now?", TITLE, 4) ~= 6 then return end

if r.IsProjectDirty(proj) == 1 and MB("The project has unsaved changes. Save it first, so the copy is up to date?", TITLE, 4) == 6 then
  r.Main_SaveProject(proj, false)
end

local _, last = r.GetProjExtState(proj, "NathanielTools", "HornDropbox")
local okIn, dbx = Inputs(TITLE, 1, "Paste the Dropbox folder:,extrawidth=420", last or "")
if not okIn then return end
dbx = trim(dbx):gsub("^file://", ""):gsub("^[\"']", ""):gsub("[\"']$", ""):gsub("%%20", " "):gsub("/$", "")
dbx = dbx:gsub("^~", os.getenv("HOME") or "~")
if not isDir(dbx) then MB("I can't find that folder:\n" .. dbx, TITLE, 0) return end
r.SetProjExtState(proj, "NathanielTools", "HornDropbox", dbx)

local folderName = base(projDir)
local dest = (base(dbx) == folderName) and dbx or (dbx .. "/" .. folderName)
local keep = dest .. "/_Replaced by JZ copy/" .. stamp
r.RecursiveCreateDirectory(horns .. "/_Logs", 0)
local logf = horns .. "/_Logs/Dropbox Copy " .. stamp .. ".log"
local note = folderName:gsub("[\"\\']", "")
local sh = table.concat({
  "/bin/mkdir -p " .. shq(dest),
  -- no --delete: nothing in Dropbox is ever removed; a file that would be replaced is kept aside first
  "/usr/bin/rsync -a --backup --backup-dir=" .. shq(keep) .. " --exclude .DS_Store " .. shq(projDir .. "/") .. " " .. shq(dest .. "/") .. " > " .. shq(logf) .. " 2>&1",
  "rc=$?",
  "/usr/bin/open " .. shq(dest),
  "if [ $rc -eq 0 ]; then /usr/bin/osascript -e 'display notification \"" .. note .. " is in Dropbox\" with title \"Horn Delivery\"'",
  "else /usr/bin/osascript -e 'display notification \"Copy to Dropbox stopped. See the log in JZ Horns.\" with title \"Horn Delivery\"'; fi",
}, "\n")
local shFile = horns .. "/_Logs/Dropbox Copy " .. stamp .. ".sh"
local fsh = io.open(shFile, "w"); fsh:write(sh .. "\n"); fsh:close()
r.ExecProcess('/bin/sh "' .. shFile .. '"', -2)     -- runs in the background; REAPER stays free
MB("Copying to:\n" .. dest .. "\n\nYou'll get a notification and the folder opens when it's done.\nNothing in Dropbox is deleted.", TITLE, 0)
