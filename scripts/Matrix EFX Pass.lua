-- @description Matrix EFX Pass (background: after a stems render from the Region Render Matrix, ticks only the EFX; after the EFX render, puts your ticks back and files the WAVs into JZ Horns)
-- @version 1.1.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about
--   Runs quietly in the background. Use the Region Render Matrix as usual:
--   1. Tick your stems and busses (not the EFX), mute the EFX, render.
--   2. The moment that render finishes, the matrix shows only the EFX ticked and the EFX is unmuted.
--      Press Render again.
--   3. When the EFX render finishes, your stem ticks and the EFX mutes come back exactly as they were,
--      and every WAV is filed in the project's JZ Horns folder:
--      trumpet tracks -> Trumpet Stems, trombone tracks -> Trombone Stems, section busses -> Submixes,
--      the TRUMPETS / TROMBONE busses -> ALL Trumpets & Trombones, and EFX.wav sits loose in JZ Horns.
--   Horn projects render with files named after their tracks ($track); a $region setting is switched over.
--   Never deletes anything: an older WAV with the same name moves to JZ Horns/Previous Renders.
--   Only acts on a project with a track called EFX. Run the action again to switch it off.
-- @changelog
--   1.1.0 - EFX.wav goes loose in JZ Horns; horn projects name files by track.
--   1.0.0 - first version.

local r = reaper
local _, _, sec, cmd = r.get_action_context()
if r.set_action_options then r.set_action_options(1) end

local EXT = "NathanielTools"
local CATS = { tpt = "Trumpet Stems", tbn = "Trombone Stems", sub = "Submixes", all = "ALL Trumpets & Trombones" }
local function catDir(horns, cat) return cat == "root" and horns or (horns .. "/" .. CATS[cat]) end   -- "root": loose in JZ Horns

local function name(tr) local _, n = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false) return n end
local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
local function isFolder(tr) return r.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") == 1 end
local function shq(s) return "'" .. s:gsub("'", "'\\''") .. "'" end

local function findEFX(proj)
  for i = 0, r.CountTracks(proj) - 1 do
    local t = r.GetTrack(proj, i); local n = trim(name(t)):upper()
    if n == "EFX" then return t end
  end
end
local function inside(t, top) while t do if t == top then return true end t = r.GetParentTrack(t) end return false end

local function regions(proj)
  local out = {}
  local _, nm, nr = r.CountProjectMarkers(proj)
  for i = 0, nm + nr - 1 do
    local _, isr, _, _, _, idx = r.EnumProjectMarkers2(proj, i)
    if isr then out[#out + 1] = idx end
  end
  out[#out + 1] = -1     -- "Entire project" column
  return out
end
local function ticks(proj, idx)
  local l, j = {}, 0
  while true do local t = r.EnumRegionRenderMatrix(proj, idx, j); if not t then break end l[#l + 1] = t; j = j + 1 end
  return l
end

local function targets(proj)
  local _, s = r.GetSetProjectInfo_String(proj, "RENDER_TARGETS", "", false)
  local l = {}
  for f in (s or ""):gmatch("[^;]+") do l[#l + 1] = f end
  return l
end
local function mtime(f)
  if not r.file_exists(f) then return nil end
  return tonumber((r.ExecProcess("/usr/bin/stat -f %m " .. shq(f), 1000) or ""):match("\n(%d+)"))
end
local function size(f) local h = io.open(f, "rb"); if not h then return -1 end local n = h:seek("end"); h:close(); return n end

local function category(tr)
  if isFolder(tr) and not r.GetParentTrack(tr) then return "all" end
  if isFolder(tr) then return "sub" end
  local t = tr
  while t do
    local n = name(t):lower()
    if n:find("trumpet") or n:find("tpt") then return "tpt" end
    if n:find("trombone") or n:find("bone") or n:find("tbn") then return "tbn" end
    t = r.GetParentTrack(t)
  end
  return "sub"
end

local function file(proj, list, efx)
  local _, projFile = r.EnumProjects(-1)
  local dir = projFile:match("^(.*)/[^/]*$"); if not dir then return 0 end
  local horns = dir .. "/JZ Horns"
  for _, c in pairs(CATS) do r.RecursiveCreateDirectory(horns .. "/" .. c, 0) end
  local byName = {}
  for i = 0, r.CountTracks(proj) - 1 do local t = r.GetTrack(proj, i); byName[trim(name(t)):lower()] = t end
  -- files named by $region come out in ticked-track order, so fall back to that order when the name says nothing
  local order = {}
  for _, idx in ipairs(regions(proj)) do
    local tk = ticks(proj, idx); table.sort(tk, function(a, b) return r.GetMediaTrackInfo_Value(a, "IP_TRACKNUMBER") < r.GetMediaTrackInfo_Value(b, "IP_TRACKNUMBER") end)
    for _, t in ipairs(tk) do order[#order + 1] = t end
  end
  local stamp, n = os.date("%Y-%m-%d %H.%M.%S"), 0
  for i, f in ipairs(list) do
    if r.file_exists(f) then
      local base = f:match("([^/]+)$"); local key = base:gsub("%.[^.]+$", ""):lower()
      local t = byName[key] or (#order == #list and order[i]) or nil
      if t and not byName[key] and trim(name(t)) ~= "" then         -- a $region-named file takes its track's name
        base = trim(name(t)):gsub("[/:\\]", "-") .. (base:match("%.[^.]+$") or ".wav")
      end
      local cat = (t == efx) and "root" or (t and category(t)) or "sub"
      local dst = catDir(horns, cat) .. "/" .. base
      if dst ~= f then
        if r.file_exists(dst) then
          local old = horns .. "/Previous Renders/" .. stamp .. (cat == "root" and "" or ("/" .. CATS[cat]))
          r.RecursiveCreateDirectory(old, 0); os.rename(dst, old .. "/" .. base)
        end
        if os.rename(f, dst) then n = n + 1 end
      end
    end
  end
  return n
end

-- one watch per project, kept on the project so a restart picks it up
local watch = {}   -- [proj] = {phase, since, list, sizes, stable}

local function serialiseTicks(proj, efx)
  local parts = {}
  for _, idx in ipairs(regions(proj)) do
    local g = {}
    for _, t in ipairs(ticks(proj, idx)) do g[#g + 1] = (t == r.GetMasterTrack(proj)) and "MASTER" or r.GetTrackGUID(t) end
    if #g > 0 then parts[#parts + 1] = idx .. ":" .. table.concat(g, ",") end
  end
  local mutes = {}
  for i = 0, r.CountTracks(proj) - 1 do
    local t = r.GetTrack(proj, i)
    if inside(t, efx) then mutes[#mutes + 1] = r.GetTrackGUID(t) .. "=" .. math.floor(r.GetMediaTrackInfo_Value(t, "B_MUTE")) end
  end
  r.SetProjExtState(proj, EXT, "MatrixBeforeEFX", table.concat(parts, "|"))
  r.SetProjExtState(proj, EXT, "EfxMutes", table.concat(mutes, ","))
end

local function toEFX(proj, efx)
  serialiseTicks(proj, efx)
  local used = {}
  for _, idx in ipairs(regions(proj)) do
    local l = ticks(proj, idx)
    if #l > 0 then for _, t in ipairs(l) do r.SetRegionRenderMatrix(proj, idx, t, -1) end used[#used + 1] = idx end
  end
  for _, idx in ipairs(used) do r.SetRegionRenderMatrix(proj, idx, efx, 1) end
  for i = 0, r.CountTracks(proj) - 1 do local t = r.GetTrack(proj, i); if inside(t, efx) then r.SetMediaTrackInfo_Value(t, "B_MUTE", 0) end end
  r.SetProjExtState(proj, EXT, "EfxPass", "efx")
  r.UpdateArrange()
end

local function back(proj)
  local byG = {}
  for i = 0, r.CountTracks(proj) - 1 do local t = r.GetTrack(proj, i); byG[r.GetTrackGUID(t)] = t end
  local _, m = r.GetProjExtState(proj, EXT, "MatrixBeforeEFX")
  for blk in m:gmatch("[^|]+") do
    local idx, list = blk:match("^(%-?%d+):(.*)$"); idx = tonumber(idx)
    for _, t in ipairs(ticks(proj, idx)) do r.SetRegionRenderMatrix(proj, idx, t, -1) end
    for g in list:gmatch("[^,]+") do
      local t = (g == "MASTER") and r.GetMasterTrack(proj) or byG[g]
      if t then r.SetRegionRenderMatrix(proj, idx, t, 1) end
    end
  end
  local _, mu = r.GetProjExtState(proj, EXT, "EfxMutes")
  for pair in mu:gmatch("[^,]+") do
    local g, v = pair:match("^(.-)=(%d)$")
    if byG[g] then r.SetMediaTrackInfo_Value(byG[g], "B_MUTE", tonumber(v)) end
  end
  r.SetProjExtState(proj, EXT, "EfxPass", "")
  r.UpdateArrange()
end

local function onlyEFX(proj, efx)
  local any = false
  for _, idx in ipairs(regions(proj)) do
    for _, t in ipairs(ticks(proj, idx)) do any = true; if t ~= efx then return false end end
  end
  return any
end

local function say(msg)   -- Claude's own tests set MatrixEFXPassLog to a file and get the message there instead of a dialog
  local log = r.GetExtState(EXT, "MatrixEFXPassLog")
  if log == "" then r.MB(msg, "Matrix EFX Pass", 0) return end
  local f = io.open(log, "a"); if f then f:write(msg .. "\n----\n"); f:close() end
end

local nextCheck = 0
local function loop()
  local now = r.time_precise()
  if now >= nextCheck then
    nextCheck = now + 1
    local proj = r.EnumProjects(-1)
    local efx = findEFX(proj)
    local useMatrix = (math.floor(r.GetSetProjectInfo(proj, "RENDER_SETTINGS", 0, false)) & 8) == 8
    if efx and useMatrix and r.GetPlayStateEx(proj) & 4 == 0 then
      local _, phase = r.GetProjExtState(proj, EXT, "EfxPass")
      local _, pat = r.GetSetProjectInfo_String(proj, "RENDER_PATTERN", "", false)
      if phase == "" and pat == "$region" then r.GetSetProjectInfo_String(proj, "RENDER_PATTERN", "$track", true) end   -- horn files are named after their tracks
      local w = watch[proj]
      local list = targets(proj)
      local want = (phase == "efx") and "efx" or "stems"
      if want == "stems" and onlyEFX(proj, efx) then list = {} end          -- he ticked the EFX himself: stay out of the way
      if not w or w.phase ~= want or #w.list ~= #list then
        w = { phase = want, since = os.time(), list = list, sizes = {}, stable = 0 }
        watch[proj] = w
      elseif #list > 0 then
        -- a render has finished when every file it writes is newer than when we started watching and has stopped growing
        local fresh, grew = true, false
        for i, f in ipairs({ list[1], list[#list] }) do
          local mt = mtime(f)
          if not mt or mt < w.since then fresh = false break end
          local s = size(f); if w.sizes[i] ~= s then grew = true end; w.sizes[i] = s
        end
        if fresh and not grew then w.stable = w.stable + 1 else w.stable = 0 end
        if w.stable >= 2 then
          if want == "stems" then
            local n = file(proj, list, efx)
            toEFX(proj, efx)
            say(n .. " stems filed in JZ Horns.\n\nThe matrix now has only the EFX ticked, and the EFX is unmuted.\nPress Render for the EFX.")
          else
            local n = file(proj, list, efx)
            back(proj)
            say("EFX rendered and filed (" .. n .. " file).\n\nYour stem ticks and the EFX mutes are back as they were.")
          end
          watch[proj] = nil
        end
      end
    end
  end
  r.defer(loop)
end

r.SetToggleCommandState(sec, cmd, 1); r.RefreshToolbar2(sec, cmd)
r.atexit(function() r.SetToggleCommandState(sec, cmd, 0); r.RefreshToolbar2(sec, cmd) end)
loop()
