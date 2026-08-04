-- @noindex
-- Shared library for the Nathaniel Tools. Not a standalone action.
-- Distributed by the packages that need it via their @provides tag.

--[[
  nt_safe.lua  -  pointer safety and stable identity for the Nathaniel Tools
  ----------------------------------------------------------------------------
  WHY THIS FILE EXISTS

  REAPER frees a MediaTrack* / ReaProject* the instant the track is deleted or
  the tab is closed.  Handing a freed pointer to any REAPER API faults inside
  REAPER's own C++.  Lua's pcall CANNOT catch that - the host process simply
  dies, taking every unsaved project with it.

  That is not a theoretical risk.  Any dockable app that caches a MediaTrack*
  in a table and reads it again on the next defer frame WILL crash REAPER the
  first time the user deletes a track with the window open.

  The only two defences that work:
    1. r.ValidatePtr2(proj, ptr, "MediaTrack*")  before every single use
    2. r.GetTrackGUID(track)  as the stored identity, never the pointer

  A GUID survives delete, undo, reorder, save/reload and tab switching.
  A pointer survives nothing.

  RULE FOR EVERY APP IN THIS SUITE:
    store GUIDs, resolve to pointers immediately before use, validate, use,
    discard.  Never hold a pointer across a frame boundary.

  Author: Jason Zac / Nathaniel School of Music
--]]

local r = reaper
local M = {}

--------------------------------------------------------------------------------
-- liveness
--------------------------------------------------------------------------------

-- A project pointer is only usable if REAPER still owns it.
--
-- NOTE, caught by the harness: 0 is ReaScript's documented shorthand for "the
-- current project", but ValidatePtr2 rejects it because 0 is not a real
-- pointer.  Without this special case every guard in the suite would silently
-- return false whenever a caller used the ordinary 0 idiom, and the app would
-- quietly do nothing at all - the worst kind of bug, because it looks like the
-- feature simply does not work.
function M.projAlive(p)
  if p == nil then return false end
  if p == 0 then return r.EnumProjects(-1) ~= nil end
  local ok, alive = pcall(r.ValidatePtr2, 0, p, "ReaProject*")
  return ok and alive == true
end

-- A track pointer is only usable if its project is alive AND it is still in it.
function M.trackAlive(proj, t)
  if t == nil then return false end
  if not M.projAlive(proj) then return false end
  local ok, alive = pcall(r.ValidatePtr2, proj, t, "MediaTrack*")
  return ok and alive == true
end

function M.itemAlive(proj, it)
  if it == nil then return false end
  if not M.projAlive(proj) then return false end
  local ok, alive = pcall(r.ValidatePtr2, proj, it, "MediaItem*")
  return ok and alive == true
end

-- DO NOT USE GetProjectStateChangeCount TO DETECT TRACK CHANGES.
--
-- Measured in REAPER 7.77 with a direct probe: the counter did NOT move when a
-- track was inserted, renamed, or deleted - it sat on 8 through all three.  Any
-- watchdog built on it silently never fires, which looks exactly like "the app
-- doesn't refresh" rather than like a bug.  Two apps in this suite shipped with
-- that dead watchdog before it was caught.
--
-- Use projSignature() instead.  It is a cheap string that changes whenever a
-- track is added, removed, renamed or reordered.  Call it on a throttle
-- (~4Hz is plenty) because it walks the track list.
function M.projSignature(proj)
  if not M.projAlive(proj) then return "dead" end
  local n = r.CountTracks(proj)
  local acc = { n }
  for i = 0, n - 1 do
    local t = r.GetTrack(proj, i)
    if t then
      acc[#acc + 1] = r.GetTrackGUID(t) .. ":" .. M.trackName(t) .. ":" ..
                      math.floor(M.getVal(proj, t, "I_FOLDERDEPTH", 0) or 0)
    end
  end
  return table.concat(acc, "|")
end

-- Kept only so older callers do not break.  It reports REAPER's counter as-is,
-- which is NOT a reliable change signal - see the note above.
function M.stateCount(p)
  if not M.projAlive(p) then return -1 end
  return r.GetProjectStateChangeCount(p)
end

--------------------------------------------------------------------------------
-- identity:  GUID  <->  live pointer
--------------------------------------------------------------------------------

-- Stable identity for a track.  Returns nil if the track is already gone,
-- which is a normal outcome, not an error.
function M.guidOf(proj, t)
  if not M.trackAlive(proj, t) then return nil end
  local ok, g = pcall(r.GetTrackGUID, t)
  if ok then return g end
  return nil
end

-- Build a fresh GUID -> MediaTrack* map.  Cheap.  Call it every frame and
-- throw it away; never store the values.
function M.guidMap(proj)
  local m = {}
  if not M.projAlive(proj) then return m end
  for i = 0, r.CountTracks(proj) - 1 do
    local t = r.GetTrack(proj, i)
    if t then
      local g = M.guidOf(proj, t)
      if g then m[g] = t end
    end
  end
  return m
end

-- Resolve one GUID to a live, validated pointer.  nil if it has gone away.
function M.resolve(proj, guid)
  if guid == nil or not M.projAlive(proj) then return nil end
  for i = 0, r.CountTracks(proj) - 1 do
    local t = r.GetTrack(proj, i)
    if t and M.guidOf(proj, t) == guid then return t end
  end
  return nil
end

-- Ordered list of { guid = ..., name = ..., track = <live ptr, this frame only> }
function M.snapshot(proj, nameFn)
  local out = {}
  if not M.projAlive(proj) then return out end
  for i = 0, r.CountTracks(proj) - 1 do
    local t = r.GetTrack(proj, i)
    if t then
      local g = M.guidOf(proj, t)
      if g then
        out[#out + 1] = {
          guid  = g,
          track = t,
          name  = nameFn and nameFn(t) or M.trackName(t),
          idx   = i,
        }
      end
    end
  end
  return out
end

--------------------------------------------------------------------------------
-- safe accessors
--   Every one of these is a no-op (or a documented default) on a dead pointer,
--   so a caller can never fault by forgetting a guard.
--------------------------------------------------------------------------------

function M.trackName(t)
  if t == nil then return "" end
  local ok, _, nm = pcall(r.GetSetMediaTrackInfo_String, t, "P_NAME", "", false)
  if ok and nm and nm ~= "" then return nm end
  local ok2, n = pcall(r.GetMediaTrackInfo_Value, t, "IP_TRACKNUMBER")
  if ok2 and n then return "Track " .. math.floor(n) end
  return ""
end

-- Read a track value, but only if the track is really there.
function M.getVal(proj, t, key, default)
  if not M.trackAlive(proj, t) then return default end
  local ok, v = pcall(r.GetMediaTrackInfo_Value, t, key)
  if ok then return v end
  return default
end

-- Write a track value, but only if the track is really there.
-- Returns true when the write actually happened.
function M.setVal(proj, t, key, v)
  if not M.trackAlive(proj, t) then return false end
  local ok = pcall(r.SetMediaTrackInfo_Value, t, key, v)
  return ok == true
end

function M.getName(proj, t)
  if not M.trackAlive(proj, t) then return "" end
  return M.trackName(t)
end

function M.setName(proj, t, nm)
  if not M.trackAlive(proj, t) then return false end
  local ok = pcall(r.GetSetMediaTrackInfo_String, t, "P_NAME", nm, true)
  return ok == true
end

--------------------------------------------------------------------------------
-- projects
--------------------------------------------------------------------------------

function M.openProjects()
  local list, i = {}, 0
  while true do
    local p, path = r.EnumProjects(i)
    if not p then break end
    if M.projAlive(p) then
      local nm = (path or ""):match("[^/\\]+$") or ""
      nm = nm:gsub("%.[Rr][Pp][Pp]$", "")
      if nm == "" then nm = "(unsaved " .. (i + 1) .. ")" end
      list[#list + 1] = { proj = p, name = nm, path = path or "", tracks = r.CountTracks(p) }
    end
    i = i + 1
  end
  return list
end

function M.projName(proj)
  if not M.projAlive(proj) then return "(closed)" end
  for _, p in ipairs(M.openProjects()) do
    if p.proj == proj then return p.name end
  end
  return "(unknown)"
end

-- Has this project ever been written to disk?  Used to avoid firing a
-- Save-As modal at someone who only wanted a silent save.
function M.projIsSaved(proj)
  if not M.projAlive(proj) then return false end
  local i = 0
  while true do
    local p, pth = r.EnumProjects(i)
    if not p then break end
    if p == proj then return (pth or "") ~= "" end
    i = i + 1
  end
  return false
end

--------------------------------------------------------------------------------
-- selection, by GUID
--------------------------------------------------------------------------------

function M.selectedGuids(proj)
  local s = {}
  if not M.projAlive(proj) then return s end
  for i = 0, r.CountSelectedTracks(proj) - 1 do
    local t = r.GetSelectedTrack(proj, i)
    local g = M.guidOf(proj, t)
    if g then s[g] = true end
  end
  return s
end

-- Save / restore a track selection across an operation that scrambles it.
function M.saveSelection(proj)
  return M.selectedGuids(proj)
end

function M.restoreSelection(proj, saved)
  if not M.projAlive(proj) or not saved then return end
  for i = 0, r.CountTracks(proj) - 1 do
    local t = r.GetTrack(proj, i)
    if t then
      local g = M.guidOf(proj, t)
      M.setVal(proj, t, "I_SELECTED", (g and saved[g]) and 1 or 0)
    end
  end
end

--------------------------------------------------------------------------------
-- record-arm / solo snapshots
--   Several of the speed-layer scripts used to clear arm or solo across the
--   WHOLE project to get a clean slate, then never put it back.  In a 452-track
--   live session that silently destroys the setup.  These let a script take a
--   scoped snapshot and restore exactly what it disturbed.
--------------------------------------------------------------------------------

function M.snapshotFlags(proj, keys)
  local snap = {}
  if not M.projAlive(proj) then return snap end
  for i = 0, r.CountTracks(proj) - 1 do
    local t = r.GetTrack(proj, i)
    local g = M.guidOf(proj, t)
    if g then
      local rec = {}
      for _, k in ipairs(keys) do rec[k] = M.getVal(proj, t, k, 0) end
      snap[g] = rec
    end
  end
  return snap
end

function M.restoreFlags(proj, snap, keys)
  if not M.projAlive(proj) or not snap then return 0 end
  local n = 0
  for i = 0, r.CountTracks(proj) - 1 do
    local t = r.GetTrack(proj, i)
    local g = M.guidOf(proj, t)
    local rec = g and snap[g]
    if rec then
      for _, k in ipairs(keys) do
        if rec[k] ~= nil then
          if M.setVal(proj, t, k, rec[k]) then n = n + 1 end
        end
      end
    end
  end
  return n
end

--------------------------------------------------------------------------------
-- dependency gate
--   Fail loudly and usefully at launch instead of erroring three clicks later.
--------------------------------------------------------------------------------

function M.require(appName, needs)
  local missing = {}
  if needs.imgui and not r.ImGui_CreateContext then
    missing[#missing + 1] =
      "ReaImGui  -  Extensions > ReaPack > Browse packages > search 'ReaImGui' > install > restart REAPER"
  end
  if needs.sws and not r.BR_GetMediaTrackSendInfo_Track then
    missing[#missing + 1] =
      "SWS extension  -  download from sws-extension.org, install, restart REAPER"
  end
  if #missing > 0 then
    r.ShowMessageBox(
      appName .. " needs:\n\n  - " .. table.concat(missing, "\n  - ") .. "\n",
      appName .. ": missing dependency", 0)
    return false
  end
  return true
end

--------------------------------------------------------------------------------
-- folder depth repair
--   A track inserted or cloned at the end of a project can leave I_FOLDERDEPTH
--   open, and REAPER then silently swallows everything after it into that
--   folder.  Walk the list and make the arithmetic well-formed.
--------------------------------------------------------------------------------

function M.normaliseFolders(proj)
  if not M.projAlive(proj) then return 0 end
  local n = r.CountTracks(proj)
  if n == 0 then return 0 end
  local depth, fixes = 0, 0
  for i = 0, n - 1 do
    local t = r.GetTrack(proj, i)
    if t then
      local fd = math.floor(M.getVal(proj, t, "I_FOLDERDEPTH", 0) or 0)
      local want = fd
      if want > 1 then want = 1 end
      if i == n - 1 then
        want = -depth                                  -- last track closes everything
      elseif want < 0 and -want > depth then
        want = -depth                                  -- never close deeper than we are
      end
      if want ~= fd then
        M.setVal(proj, t, "I_FOLDERDEPTH", want)
        fixes = fixes + 1
      end
      depth = depth + want
      if depth < 0 then depth = 0 end
    end
  end
  return fixes
end

return M
