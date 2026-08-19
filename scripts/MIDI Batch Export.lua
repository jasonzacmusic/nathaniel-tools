-- @description MIDI Batch Export
-- @version 2.0.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about Export many MIDI items or regions as separate .mid files in one go,
--   named from a pattern ($num, $name, $track, $region, $project, $bpm).
--   Every file carries the tempo and time signature at its own start, at the
--   item's own tick resolution, so it opens at the right speed anywhere.
--   Requires the "Shared Libraries" package from this same repository
--   (right-click the repository in ReaPack > Install All).
-- @changelog
--   2.0.0 - new shared look (nt_ui): header, one status line + log, confirm
--           before replacing files, empty state, Choose... folder button,
--           system font. The files themselves are now correct MIDI: tick
--           resolution is read from the item (was hard-wired to 960), text /
--           notation / sysex events get their proper length fields (were
--           written raw and could break the file), and tempo + time signature
--           are taken at the item's own start (was the master tempo and bar 1).
--           "Notes only" now also leaves out muted notes and REAPER's notation.
--           Rows remember items by identity, so deleting an item while the
--           window is open can no longer crash REAPER. Regions holding several
--           MIDI items say so in the list BEFORE you export. New $region name.
--   1.0.0 - first public release.

--[[
  MIDI Batch Export        Nathaniel Tools  -  amber (delivery)
  ----------------------------------------------------------------------------
  THE PROBLEM THIS SOLVES

  REAPER's "File > Export project MIDI" (action 40849) exports ONE file, from a
  time selection, behind a modal dialog.  Exporting seven riffs as seven
  numbered .mid files therefore means doing the whole dance seven times and
  typing seven filenames by hand.

  This exports every selected item / region / track in one pass, writing each to
  its own Standard MIDI File with names generated from a pattern.  No modal, no
  typing, no chance of two files silently overwriting each other: the list shows
  the exact filename each row will produce, flags clashes and existing files,
  and asks before it replaces anything.

  HOW IT WRITES THE FILES

  It does not drive 40849 at all.  It reads the MIDI with MIDI_GetAllEvts and
  writes the SMF bytes directly, which is what makes a batch possible.

    * Tick resolution: read from the item itself (ticks per project quarter
      note, which also absorbs the item's play rate), not assumed.
    * Tempo + time signature: the values in force at the ITEM'S START, written
      as meta events, so a riff at bar 57 opens at bar 57's tempo.
    * Text, REAPER notation and sysex: written with the length fields the SMF
      spec wants (REAPER hands them back without).
    * "Notes only": note-on / note-off only, muted notes dropped, no CC, no
      pitch bend, no notation, no sysex.  Off = a faithful copy of everything.
    * Regions: one file per region, holding the FIRST MIDI item that starts
      inside it.  A region with several MIDI items is flagged in the list.

  Pointer safety: rows key on the item's identity, never on raw pointers,
  and every pointer is resolved and validated at export time.  See
  scripts/lib/nt_safe.lua for why that is not optional.

  Requires ReaImGui and the Shared Libraries package.  SWS / js_ReaScriptAPI
  optional (nicer folder picker and Finder reveal).
--]]

local r = reaper

--------------------------------------------------------------------------------
-- libraries
--------------------------------------------------------------------------------
do
  local sep = package.config:sub(1, 1)
  local here = ({ r.get_action_context() })[2]:match("(.*" .. sep .. ")") or ""
  package.path = here .. "lib" .. sep .. "?.lua;" ..
                 r.GetResourcePath() .. "/Scripts/Nathaniel Tools/scripts/lib/?.lua;" ..
                 package.path
end
local okSafe, safe = pcall(require, "nt_safe")
local okUi,   ui   = pcall(require, "nt_ui")
if not (okSafe and okUi) then
  r.ShowMessageBox("MIDI Batch Export needs the 'Shared Libraries' package.\n\n" ..
    "Extensions > ReaPack > Browse packages > search 'Nathaniel Tools' > Shared Libraries > Install.\n" ..
    "(Or right-click the Nathaniel Tools repository > Install All.)", "MIDI Batch Export", 0)
  return
end
do local ok, compat = pcall(require, "nt_imgui"); if ok then compat.install() end end
if not safe.require("MIDI Batch Export", { imgui = true }) then return end

local APP = "MIDI Batch Export"
local T = ui.tokens

--------------------------------------------------------------------------------
-- project / item helpers  (identity, never pointers, across frames)
--------------------------------------------------------------------------------
local function activeProj() return r.EnumProjects(-1) end
local tName = safe.trackName

-- Stable identity for an item. SWS gives it directly; REAPER itself via the
-- "GUID" string key. Either survives delete/undo/reorder; a pointer does not.
local function itemGuid(it)
  if r.BR_GetMediaItemGUID then
    local ok, g = pcall(r.BR_GetMediaItemGUID, it)
    if ok and g and g ~= "" then return g end
  end
  local ok, rv, g = pcall(r.GetSetMediaItemInfo_String, it, "GUID", "", false)
  if ok and rv and g and g ~= "" then return g end
  return nil
end

-- Fresh identity -> live pointer map. Build it, use it, throw it away.
local function itemMap(proj)
  local m = {}
  if not safe.projAlive(proj) then return m end
  for i = 0, r.CountMediaItems(proj) - 1 do
    local it = r.GetMediaItem(proj, i)
    if it then
      local g = itemGuid(it)
      if g then m[g] = it end
    end
  end
  return m
end

local function projPath(proj)
  local i = 0
  while true do
    local p, pth = r.EnumProjects(i)
    if not p then break end
    if p == proj then return pth or "" end
    i = i + 1
  end
  return ""
end
local function projectName(proj)
  local nm = projPath(proj):match("[^/\\]+$") or ""
  nm = nm:gsub("%.[Rr][Pp][Pp]$", "")
  if nm == "" then nm = "untitled" end
  return nm
end
local function defaultDir(proj)
  local d = projPath(proj):match("^(.*)[/\\][^/\\]+$")
  if d and d ~= "" then return d .. "/MIDI Export" end
  return (r.GetProjectPath("") or "") .. "/MIDI Export"
end

-- Name of the region a position sits inside, or "".
local function regionNameAt(proj, pos)
  if not r.GetLastMarkerAndCurRegion then return "" end
  local _, rgn = r.GetLastMarkerAndCurRegion(proj, pos)
  if not rgn or rgn < 0 then return "" end
  local ok, isrgn, _, _, nm, num = r.EnumProjectMarkers3(proj, rgn)
  if ok == 0 or not isrgn then return "" end
  if nm and nm ~= "" then return nm end
  return "Region " .. tostring(num or (rgn + 1))
end

-- Tempo and time signature in force at a project position.
--   num, den   the time signature
--   tempo      the tempo as REAPER shows it at that point (for the $bpm name)
--   qbpm       quarter notes per minute, measured straight off the time map -
--              which is exactly what an SMF tempo event means, whatever REAPER's
--              tempo/denominator setting is
local function tempoAt(proj, pos)
  local num, den, tempo = r.TimeMap_GetTimeSigAtTime(proj, pos)
  num   = (num and num > 0) and math.floor(num) or 4
  den   = (den and den > 0) and math.floor(den) or 4
  tempo = (tempo and tempo > 0) and tempo or 120
  local qbpm = tempo
  local qn = r.TimeMap2_timeToQN(proj, pos)
  local t1 = r.TimeMap2_QNToTime(proj, qn + 0.25)
  if t1 and t1 > pos then qbpm = 15 / (t1 - pos) end       -- 60 * 0.25 quarter
  return num, den, tempo, qbpm
end

local function barOf(pos)
  local ok, s = pcall(r.format_timestr_pos, pos, "", 2)      -- measures.beats
  if ok and s and s ~= "" then return "bar " .. s end
  return ("%.2fs"):format(pos)
end

--------------------------------------------------------------------------------
-- Standard MIDI File writer
--   SMF is big-endian.  Delta times and lengths are variable-length quantities.
--------------------------------------------------------------------------------
local function be32(n)
  return string.char((n >> 24) & 255, (n >> 16) & 255, (n >> 8) & 255, n & 255)
end
local function be16(n)
  return string.char((n >> 8) & 255, n & 255)
end
local function varlen(n)
  n = math.floor(n or 0)
  if n < 0 then n = 0 end
  local out = { n & 0x7F }
  n = n >> 7
  while n > 0 do
    table.insert(out, 1, (n & 0x7F) | 0x80)
    n = n >> 7
  end
  return string.char(table.unpack(out))
end
local function chunk(id, data)
  return id .. be32(#data) .. data
end

-- meta events (each with a zero delta; they open the track)
local function metaTempo(qbpm)
  if not qbpm or qbpm <= 0 then qbpm = 120 end
  local uspq = math.floor(60000000 / qbpm + 0.5)
  if uspq < 1 then uspq = 1 elseif uspq > 0xFFFFFF then uspq = 0xFFFFFF end
  return varlen(0) .. "\xFF\x51\x03" ..
         string.char((uspq >> 16) & 255, (uspq >> 8) & 255, uspq & 255)
end
local function metaTimeSig(num, den)
  num = math.max(1, math.min(255, math.floor(num or 4)))
  den = math.max(1, math.floor(den or 4))
  -- SMF stores the denominator as a power of two
  local dd, v = 0, den
  while v > 1 do v = v // 2; dd = dd + 1 end
  return varlen(0) .. "\xFF\x58\x04" .. string.char(num, dd, 24, 8)
end
local function metaTrackName(nm)
  nm = tostring(nm or "")
  return varlen(0) .. "\xFF\x03" .. varlen(#nm) .. nm
end

-- Convert one MIDI take into SMF bytes.
--
-- REAPER's MIDI_GetAllEvts gives: int32 LE offset (delta ticks since the
-- previous event), uint8 flag (&1 selected, &2 muted, high bits = CC shape),
-- int32 LE msglen, then the message.  Offsets are deltas in the take's own
-- ticks, which map one-for-one onto SMF delta times.  Meta events come back as
-- FF <type> <bytes...> and sysex as F0 <bytes...> F7 - WITHOUT the length
-- field an SMF needs, so we put it in here.
--
-- opts = { name=, notesOnly= }
local function takeToSMF(proj, item, take, opts)
  if not take or not r.TakeIsMIDI(take) then return nil, "not a MIDI item" end
  local ok, buf = r.MIDI_GetAllEvts(take, "")
  if not ok or not buf or #buf == 0 then return nil, "the item holds no MIDI" end

  -- ticks per project quarter note, read from the take itself
  local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
  local qn  = r.TimeMap2_timeToQN(proj, pos)
  local p0  = r.MIDI_GetPPQPosFromProjQN(take, qn)
  local p1  = r.MIDI_GetPPQPosFromProjQN(take, qn + 1)
  local ppqRaw = (p1 or 0) - (p0 or 0)
  local ppq = math.floor(ppqRaw + 0.5)
  if ppq < 1 or ppq > 32767 then
    return nil, ("unusual tick resolution (%.2f ticks per quarter note) - cannot be stored in a MIDI file"):format(ppqRaw)
  end

  local num, den, _, qbpm = tempoAt(proj, pos)

  local body = {}
  body[#body + 1] = metaTrackName(opts.name or "")
  body[#body + 1] = metaTempo(qbpm)
  body[#body + 1] = metaTimeSig(num, den)

  local i, n = 1, #buf
  local carried = 0        -- delta of any event we skip must not be lost
  local wrote = 0
  while i + 8 <= n do
    local offset, flag, len = string.unpack("<i4Bi4", buf, i)
    i = i + 9
    if len < 0 or i + len - 1 > n then break end
    local msg = buf:sub(i, i + len - 1)
    i = i + len

    if offset < 0 then offset = 0 end
    local delta = carried + offset
    local out = nil
    if len >= 1 then
      local status = msg:byte(1)
      local muted  = (flag & 2) ~= 0
      if status == 0xFF then
        -- meta: FF type bytes...   (we write our own end-of-track, drop theirs)
        local mtype = (len >= 2) and msg:byte(2) or nil
        if mtype and mtype ~= 0x2F and not opts.notesOnly then
          local payload = msg:sub(3)
          out = "\xFF" .. string.char(mtype) .. varlen(#payload) .. payload
        end
      elseif status == 0xF0 then
        -- sysex: F0 bytes... F7  -> F0 <len> bytes... F7
        if not opts.notesOnly then
          local payload = msg:sub(2)
          if payload:byte(-1) ~= 0xF7 then payload = payload .. "\xF7" end
          out = "\xF0" .. varlen(#payload) .. payload
        end
      elseif status == 0xF7 then
        -- escaped / continued sysex
        if not opts.notesOnly then
          local payload = msg:sub(2)
          out = "\xF7" .. varlen(#payload) .. payload
        end
      elseif status >= 0xF1 then
        -- system common / realtime bytes have no place in a file
      elseif status >= 0x80 then
        local kind = status & 0xF0
        local keep = true
        if opts.notesOnly then
          keep = (kind == 0x80 or kind == 0x90) and not muted
        end
        if keep then out = msg end
      end
    end
    if out then
      body[#body + 1] = varlen(delta) .. out
      carried = 0
      wrote = wrote + 1
    else
      carried = delta
    end
  end

  if wrote == 0 then
    return nil, opts.notesOnly and "no notes in this item" or "no MIDI events in this item"
  end
  -- end of track, keeping the distance to the last (possibly skipped) event so
  -- the file is as long as the item
  body[#body + 1] = varlen(carried) .. "\xFF\x2F\x00"

  local trk = chunk("MTrk", table.concat(body))
  local hdr = chunk("MThd", be16(0) .. be16(1) .. be16(ppq))   -- format 0, 1 track
  return hdr .. trk
end

--------------------------------------------------------------------------------
-- naming
--------------------------------------------------------------------------------
local ILLEGAL = '[/\\%?%%%*:|"<>]'
local function sanitise(s)
  s = tostring(s or ""):gsub(ILLEGAL, "-")
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  return s
end

-- Words:  $num  $name  $track  $region  $project  $bpm
local function expand(pattern, vars, num, pad)
  local numStr  = string.format("%0" .. pad .. "d", num)
  local name    = sanitise(vars.name)
  local track   = sanitise(vars.track)
  local region  = sanitise(vars.region)
  local project = sanitise(vars.project)
  local bpm     = tostring(math.floor((vars.bpm or 120) + 0.5))
  local out = pattern
  out = out:gsub("%$num",     function() return numStr end)
  out = out:gsub("%$name",    function() return name end)
  out = out:gsub("%$track",   function() return track end)
  out = out:gsub("%$region",  function() return region end)
  out = out:gsub("%$project", function() return project end)
  out = out:gsub("%$bpm",     function() return bpm end)
  out = sanitise(out)
  if out == "" then out = "untitled" end
  return out
end

--------------------------------------------------------------------------------
-- gathering  (one row per file we will write; rows hold identities only)
--------------------------------------------------------------------------------
local SOURCES = {
  { id = "sel",     label = "Selected items",
    tip = "One .mid per selected MIDI item in the arrange window." },
  { id = "tracks",  label = "Items on selected tracks",
    tip = "One .mid per MIDI item on the tracks that are selected." },
  { id = "regions", label = "Regions",
    tip = "One .mid per region, holding the FIRST MIDI item that starts inside it. A region with several MIDI items is flagged in the list - split the region, or use 'Selected items', if you need each of them." },
  { id = "all",     label = "Every MIDI item",
    tip = "One .mid per MIDI item in the whole project." },
}
local EMPTY_HINT = {
  sel     = "Select some MIDI items in the arrange window - the list follows your selection.",
  tracks  = "Select the tracks that hold MIDI - the list follows your track selection.",
  regions = "Add regions over your MIDI items. A region with no MIDI item inside is skipped.",
  all     = "This project has no MIDI items yet.",
}

-- Describe one MIDI item (nil if it is not a MIDI item). Called at build time.
local function describeItem(proj, it)
  if not safe.itemAlive(proj, it) then return nil end
  local take = r.GetActiveTake(it)
  if not take or not r.TakeIsMIDI(take) then return nil end
  local g = itemGuid(it)
  if not g then return nil end
  local tr  = r.GetMediaItem_Track(it)
  local pos = r.GetMediaItemInfo_Value(it, "D_POSITION")
  local _, takeName = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
  local trackName = tName(tr)
  local trackIdx  = tr and (r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") or 0) or 0
  local _, _, tempo = tempoAt(proj, pos)
  return {
    guid     = g,
    name     = (takeName ~= "" and takeName) or trackName,
    track    = trackName,
    trackIdx = trackIdx,
    pos      = pos,
    bpm      = tempo,
    region   = regionNameAt(proj, pos),
  }
end

local function gather(proj, source)
  local out = {}
  if not safe.projAlive(proj) then return out end

  local function addItem(it)
    local d = describeItem(proj, it)
    if not d then return end
    d.key, d.on = d.guid, true
    out[#out + 1] = d
  end

  if source == "sel" then
    for i = 0, r.CountSelectedMediaItems(proj) - 1 do
      addItem(r.GetSelectedMediaItem(proj, i))
    end
  elseif source == "tracks" then
    local sel = {}
    for i = 0, r.CountSelectedTracks(proj) - 1 do
      local t = r.GetSelectedTrack(proj, i)
      if t then sel[r.GetTrackGUID(t)] = true end
    end
    for i = 0, r.CountMediaItems(proj) - 1 do
      local it = r.GetMediaItem(proj, i)
      if it then
        local t = r.GetMediaItem_Track(it)
        if t and sel[r.GetTrackGUID(t)] then addItem(it) end
      end
    end
  elseif source == "all" then
    for i = 0, r.CountMediaItems(proj) - 1 do addItem(r.GetMediaItem(proj, i)) end
  else
    -- Regions: one file per region, from the FIRST MIDI item that starts in it.
    local all = {}
    for i = 0, r.CountMediaItems(proj) - 1 do
      local d = describeItem(proj, r.GetMediaItem(proj, i))
      if d then all[#all + 1] = d end
    end
    table.sort(all, function(a, b)
      if math.abs(a.pos - b.pos) > 1e-9 then return a.pos < b.pos end
      return a.trackIdx < b.trackIdx
    end)
    local idx = 0
    while true do
      local ok, isrgn, s, e, nm, num = r.EnumProjectMarkers3(proj, idx)
      if ok == 0 then break end
      if isrgn then
        local members = {}
        for _, d in ipairs(all) do
          if d.pos >= s - 1e-9 and d.pos < e - 1e-9 then members[#members + 1] = d end
        end
        if #members > 0 then
          local first = members[1]
          local guids = {}
          for _, d in ipairs(members) do guids[#guids + 1] = d.guid end
          local rname = (nm ~= "" and nm) or ("Region " .. tostring(num or (idx + 1)))
          local _, _, tempo = tempoAt(proj, s)
          out[#out + 1] = {
            key       = "region:" .. tostring(num or idx) .. ":" .. rname,
            isRegion  = true,
            guids     = guids,
            count     = #members,
            firstDesc = ("%s, %s"):format(first.track ~= "" and first.track or "unnamed track", barOf(first.pos)),
            name      = rname,
            track     = first.track,
            trackIdx  = first.trackIdx,
            pos       = s,
            bpm       = tempo,
            region    = rname,
            on        = true,
          }
        end
      end
      idx = idx + 1
    end
  end

  table.sort(out, function(a, b)
    if math.abs(a.pos - b.pos) > 1e-9 then return a.pos < b.pos end
    return (a.trackIdx or 0) < (b.trackIdx or 0)
  end)
  return out
end

--------------------------------------------------------------------------------
-- state
--------------------------------------------------------------------------------
local ctx = r.ImGui_CreateContext(APP)
ui.fonts(ctx)

local rows      = {}
local source    = "sel"
local pattern   = "$num - $name"
local startNum  = 1
local padding   = 2
local outDir    = ""
local notesOnly = false
local overwrite = false
local paint     = {}
local confirmOpts = {}
local lastSig, lastSigT = nil, 0

local function say(msg, level) ui.say(ctx, msg, level) end

-- Change detection. NOT GetProjectStateChangeCount: measured in REAPER 7.77 that
-- counter does NOT move when a track or item is added, renamed or deleted, so a
-- watchdog built on it never fires. We diff a cheap signature instead: tracks
-- (names, order), items (position, selection), selected tracks and regions.
local function projSig(proj)
  if not safe.projAlive(proj) then return "dead" end
  local acc = { safe.projSignature(proj), r.CountMediaItems(proj),
                r.CountSelectedMediaItems(proj), r.CountSelectedTracks(proj) }
  for i = 0, r.CountMediaItems(proj) - 1 do
    local it = r.GetMediaItem(proj, i)
    if it then
      acc[#acc + 1] = string.format("%.4f%s", r.GetMediaItemInfo_Value(it, "D_POSITION"),
                                    r.IsMediaItemSelected(it) and "s" or "")
    end
  end
  for i = 0, r.CountSelectedTracks(proj) - 1 do
    local t = r.GetSelectedTrack(proj, i)
    if t then acc[#acc + 1] = r.GetTrackGUID(t) end
  end
  local idx = 0
  while true do
    local ok, isrgn, s, e, nm = r.EnumProjectMarkers3(proj, idx)
    if ok == 0 then break end
    if isrgn then acc[#acc + 1] = string.format("%.4f-%.4f%s", s, e, nm or "") end
    idx = idx + 1
  end
  return table.concat(acc, "|")
end

local function rebuild()
  local proj = activeProj()
  local keep = {}
  for _, row in ipairs(rows) do keep[row.key] = row.on end
  rows = gather(proj, source)
  for _, row in ipairs(rows) do
    if keep[row.key] ~= nil then row.on = keep[row.key] end
  end
  lastSig = projSig(proj)
  if outDir == "" then outDir = defaultDir(proj) end
end

local function foundMsg()
  local n = #rows
  local s = n == 1 and "" or "s"
  if source == "sel" then return ("%d selected MIDI item%s in the list."):format(n, s)
  elseif source == "tracks" then return ("%d MIDI item%s on the selected tracks."):format(n, s)
  elseif source == "regions" then return ("%d region%s with MIDI inside."):format(n, s)
  else return ("%d MIDI item%s in the project."):format(n, s) end
end

--------------------------------------------------------------------------------
-- files on disk
--------------------------------------------------------------------------------
local function ensureDir(path)
  if r.RecursiveCreateDirectory then r.RecursiveCreateDirectory(path, 0) end
end
local function fileExists(p)
  local f = io.open(p, "rb")
  if f then f:close(); return true end
  return false
end
-- The list asks "does this file exist?" every frame; ask the disk at most once
-- a second per name.
local existsCache, existsT = {}, 0
local function cachedExists(p)
  local now = r.time_precise()
  if now - existsT > 1.0 then existsCache = {}; existsT = now end
  local v = existsCache[p]
  if v == nil then v = fileExists(p); existsCache[p] = v end
  return v
end
local function reveal(path)
  if r.CF_ShellExecute then r.CF_ShellExecute(path)
  elseif r.GetOS():match("OSX") or r.GetOS():match("macOS") then os.execute('open "' .. path .. '"')
  else os.execute('start "" "' .. path .. '"') end
end

-- Filenames for the ticked rows, with clash and already-exists detection.
-- Returns list, clashes, exists, dir
--   list[i] = { row=, file=, num=, clash=, exists= }
local function plan()
  local proj = activeProj()
  local dir = outDir ~= "" and outDir or defaultDir(proj)
  local vars = { project = projectName(proj) }
  local list, count = {}, {}
  local n = startNum
  for _, row in ipairs(rows) do
    if row.on then
      vars.name, vars.track, vars.region, vars.bpm = row.name, row.track, row.region, row.bpm
      local fn = expand(pattern, vars, n, padding) .. ".mid"
      local key = fn:lower()
      count[key] = (count[key] or 0) + 1
      list[#list + 1] = { row = row, file = fn, num = n, key = key }
      n = n + 1
    end
  end
  local clashes, exists = 0, 0
  for _, e in ipairs(list) do
    e.clash  = count[e.key] > 1
    e.exists = cachedExists(dir .. "/" .. e.file)
    if e.clash then clashes = clashes + 1 end
    if e.exists then exists = exists + 1 end
  end
  return list, clashes, exists, dir
end

--------------------------------------------------------------------------------
-- export
--------------------------------------------------------------------------------
local function doExport()
  local proj = activeProj()
  if not safe.projAlive(proj) then say("No project is open.", "danger"); return end

  local list, clashes, _, dir = plan()
  if #list == 0 then say("Nothing ticked. Tick the rows you want first.", "warn"); return end
  if clashes > 0 and not overwrite then
    say(("Stopped: %d rows would write the same file name, so one would silently replace the other. Add $num or $track to the name, or tick 'Allow overwrite' if you really mean it."):format(clashes), "danger")
    return
  end

  outDir = dir
  ensureDir(outDir)
  local map = itemMap(proj)     -- identities -> live pointers, this call only

  local written, skipped, failed = 0, 0, 0
  for _, entry in ipairs(list) do
    local row  = entry.row
    local path = outDir .. "/" .. entry.file
    local handled = false

    if fileExists(path) and not overwrite then
      say(("Skipped %s - already there (tick 'Allow overwrite' to replace it)."):format(entry.file), "warn")
      skipped = skipped + 1
      handled = true
    end

    if not handled then
      -- Resolve the item fresh. Anything deleted since the list was built is
      -- reported, never dereferenced.
      local item, note = nil, nil
      if row.isRegion then
        for k, g in ipairs(row.guids) do
          local it = map[g]
          if safe.itemAlive(proj, it) then
            item = it
            if k > 1 then note = ("the region's first MIDI item was deleted, wrote item %d instead"):format(k) end
            break
          end
        end
      else
        local it = map[row.guid]
        if safe.itemAlive(proj, it) then item = it end
      end

      if not item then
        say(("%s - the item was deleted since the list was built, nothing written."):format(entry.file), "danger")
        failed = failed + 1
      else
        local take = r.GetActiveTake(item)
        local data, err = takeToSMF(proj, item, take, { name = row.name, notesOnly = notesOnly })
        if not data then
          say(("%s - %s."):format(entry.file, tostring(err)), "danger")
          failed = failed + 1
        else
          local f = io.open(path, "wb")
          if not f then
            say(("%s - could not write to %s. Is the folder writable?"):format(entry.file, outDir), "danger")
            failed = failed + 1
          else
            f:write(data); f:close()
            local extra = ""
            if row.isRegion and row.count > 1 then
              extra = (" (region holds %d MIDI items, wrote the first)"):format(row.count)
            end
            if note then extra = " (" .. note .. ")" end
            say(("Wrote %s - %d bytes%s"):format(entry.file, #data, extra), "info")
            written = written + 1
          end
        end
      end
    end
  end

  existsCache = {}
  local summary = ("Done: %d written, %d skipped, %d failed - %s"):format(written, skipped, failed, outDir)
  if failed > 0 then say(summary .. "  (open the log to see which)", "danger")
  elseif skipped > 0 then say(summary, "warn")
  else say(("Wrote %d file%s to %s"):format(written, written == 1 and "" or "s", outDir), "ok") end
end

-- What the EXPORT button does: straight to work, or a warning first when files
-- are about to be replaced.
local function startExport(list, clashes, exists, dir)
  if #list == 0 then say("Nothing ticked. Tick the rows you want first.", "warn"); return end
  if clashes > 0 and not overwrite then
    say(("Stopped: %d rows would write the same file name, so one would silently replace the other. Add $num or $track to the name, or tick 'Allow overwrite' if you really mean it."):format(clashes), "danger")
    return
  end
  if overwrite and (exists > 0 or clashes > 0) then
    local bits = {}
    if exists > 0 then
      bits[#bits + 1] = ("%d of the %d files already exist in %s and will be replaced."):format(exists, #list, dir)
    end
    if clashes > 0 then
      bits[#bits + 1] = ("%d rows share a file name, so the later one replaces the earlier one."):format(clashes)
    end
    confirmOpts = {
      title  = "Replace existing files?",
      text   = table.concat(bits, " ") .. " This cannot be undone.",
      ok     = "Replace and export",
      danger = true,
    }
    ui.ask(ctx, "export")
    return
  end
  doExport()
end

--------------------------------------------------------------------------------
-- frame
--------------------------------------------------------------------------------
local function frame()
  ui.header(ctx, APP, "many .mid files in one go", function() ui.dockToggle(ctx) end, 70)

  -- what
  ui.section(ctx, "What to export")
  local ns = ui.segmented(ctx, "source", SOURCES, source)
  if ns ~= source then source = ns; rebuild(); say(foundMsg(), "info") end
  r.ImGui_SameLine(ctx, 0, 14)
  if ui.button(ctx, "Refresh", { small = true,
      tip = "Read the project again: selection, tracks, regions and items. The list also refreshes by itself when the project changes." }) then
    rebuild(); say(foundMsg(), "info")
  end

  -- naming
  ui.section(ctx, "How to name them")
  r.ImGui_AlignTextToFramePadding(ctx); ui.hint(ctx, "Name")
  r.ImGui_SameLine(ctx); r.ImGui_SetNextItemWidth(ctx, 280)
  local pc, pv = r.ImGui_InputText(ctx, "##pat", pattern); if pc then pattern = pv end
  ui.tip(ctx, "How each file is named. Words you can use:\n" ..
              "$num - running number\n" ..
              "$name - the item's name, or its track's name if it has none\n" ..
              "$track - track name\n" ..
              "$region - the region the item starts in\n" ..
              "$project - project name\n" ..
              "$bpm - tempo at the item's start\n" ..
              "Example:  Riff $num - $name")
  r.ImGui_SameLine(ctx, 0, 14); r.ImGui_AlignTextToFramePadding(ctx); ui.hint(ctx, "start at")
  r.ImGui_SameLine(ctx); r.ImGui_SetNextItemWidth(ctx, 64)
  local sc, sv = r.ImGui_InputInt(ctx, "##start", startNum, 0); if sc then startNum = math.max(0, sv) end
  ui.tip(ctx, "The first $num. The rows count up from here in list order.")
  r.ImGui_SameLine(ctx, 0, 14); r.ImGui_AlignTextToFramePadding(ctx); ui.hint(ctx, "digits")
  r.ImGui_SameLine(ctx); r.ImGui_SetNextItemWidth(ctx, 64)
  local dc, dv = r.ImGui_InputInt(ctx, "##pad", padding, 0); if dc then padding = math.min(6, math.max(1, dv)) end
  ui.tip(ctx, "How many digits $num is padded to. 2 gives 01, 02, 03 ... so the files sort in order.")
  local ch, v
  ch, v = ui.toggle(ctx, "Notes only", notesOnly,
    "Keep only the notes: no mod wheel / sustain / other CC, no pitch bend, no aftertouch, no program changes, no text, no REAPER notation, no sysex - and muted notes are left out.\n" ..
    "Off = a faithful copy of everything in the item. Muted notes are kept too, and will play in the file.")
  if ch then notesOnly = v end
  r.ImGui_SameLine(ctx, 0, 18)
  ch, v = ui.toggle(ctx, "Allow overwrite", overwrite,
    "Off: a file that already exists is left alone and that row is skipped.\n" ..
    "On: existing files are replaced - you get one warning first.")
  if ch then overwrite = v end

  -- where
  ui.section(ctx, "Where")
  r.ImGui_SetNextItemWidth(ctx, -170)
  local oc, ov = r.ImGui_InputText(ctx, "##dir", outDir); if oc then outDir = ov; existsCache = {} end
  ui.tip(ctx, "Folder for the .mid files. It is created if it does not exist.")
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "Choose...", { tip = r.JS_Dialog_BrowseForFolder and "Pick the folder." or "Needs the js_ReaScriptAPI extension (ReaPack) for a folder picker. Type or paste the folder instead.",
      disabled = not r.JS_Dialog_BrowseForFolder }) then
    local rv, path = r.JS_Dialog_BrowseForFolder("MIDI export folder", outDir)
    if rv == 1 and path and path ~= "" then outDir = path; existsCache = {} end
  end
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "Reveal", { tip = "Open the folder in Finder / Explorer." }) then
    if outDir == "" then outDir = defaultDir(activeProj()) end
    ensureDir(outDir); reveal(outDir)
    say("Opened " .. outDir, "info")
  end

  -- files
  ui.section(ctx, "Files")
  local list, clashes, exists, dir = plan()
  local n = #list
  if #rows == 0 then
    ui.empty(ctx, "Nothing to export yet", EMPTY_HINT[source] or "",
      { button = "Refresh", onClick = function() rebuild(); say(foundMsg(), "info") end })
  else
    local plural = n == 1 and "" or "s"
    if clashes > 0 then
      ui.wrapped(ctx, ("%d file%s - but %d would share the same name and replace each other. Add $num or $track to the name."):format(n, plural, clashes), T.danger)
    elseif exists > 0 and not overwrite then
      ui.wrapped(ctx, ("%d file%s to %s - %d already exist and will be skipped (tick 'Allow overwrite' to replace them)."):format(n, plural, dir, exists), T.warn)
    elseif exists > 0 then
      ui.wrapped(ctx, ("%d file%s to %s - %d already exist and WILL be replaced."):format(n, plural, dir, exists), T.warn)
    elseif n == 0 then
      ui.hint(ctx, "Nothing ticked - tick the rows you want to write.")
    else
      ui.wrapped(ctx, ("%d file%s will be written to %s"):format(n, plural, dir), T.muted)
    end

    if ui.tableBegin(ctx, "files",
        { { name = "", w = 30 }, { name = "Source" }, { name = "Track", w = 150 }, { name = "Writes file" } },
        { reserve = 96 }) then
      local planOf = {}
      for _, e in ipairs(list) do planOf[e.row] = e end
      for i, row in ipairs(rows) do
        r.ImGui_TableNextRow(ctx); r.ImGui_PushID(ctx, i)
        r.ImGui_TableNextColumn(ctx)
        local c, val = ui.tick(ctx, "##on", row.on, paint); if c then row.on = val end
        r.ImGui_TableNextColumn(ctx)
        r.ImGui_Text(ctx, row.name)
        if row.isRegion and row.count > 1 then
          r.ImGui_SameLine(ctx, 0, 8)
          ui.pill(ctx, ("first of %d"):format(row.count), T.warn)
          ui.tip(ctx, ("This region holds %d MIDI items. Only the FIRST one is written: %s. Split the region, or switch to 'Selected items', if you need each of them."):format(row.count, row.firstDesc))
        end
        r.ImGui_TableNextColumn(ctx); ui.text(ctx, row.track or "", T.muted)
        r.ImGui_TableNextColumn(ctx)
        local e = planOf[row]
        if e then
          if e.clash then ui.text(ctx, e.file .. "  (same name as another row)", T.danger)
          elseif e.exists then ui.text(ctx, e.file .. (overwrite and "  (will be replaced)" or "  (exists - skipped)"), T.warn)
          else ui.text(ctx, e.file, T.ok) end
        else
          ui.text(ctx, "-", T.dim)
        end
        r.ImGui_PopID(ctx)
      end
      r.ImGui_EndTable(ctx)
    end
  end

  -- the big button + tick helpers
  local label = n == 1 and "EXPORT 1 FILE" or ("EXPORT %d FILES"):format(n)
  if ui.button(ctx, label, { kind = "primary", w = 220, h = 34, disabled = n == 0,
      tip = "Writes the .mid files now. Nothing in your project changes." }) then
    startExport(list, clashes, exists, dir)
  end
  r.ImGui_SameLine(ctx, 0, 14)
  if ui.button(ctx, "All", { small = true, tip = "Tick every row." }) then for _, x in ipairs(rows) do x.on = true end end
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "None", { small = true, tip = "Untick every row." }) then for _, x in ipairs(rows) do x.on = false end end

  if ui.confirm(ctx, "export", confirmOpts) then doExport() end

  ui.status(ctx, { idle = "Pick what to export, name the files, press Export." })
end

--------------------------------------------------------------------------------
-- loop
--------------------------------------------------------------------------------
rebuild()
local function loop()
  local p = activeProj()
  if not safe.projAlive(p) then rows = {}
  else
    local now = r.time_precise()
    if now - lastSigT > 0.25 then      -- throttled: the signature walks every item
      lastSigT = now
      if projSig(p) ~= lastSig then rebuild() end
    end
  end
  local open = ui.window(ctx, { title = APP, accent = ui.accents.amber, w = 880, h = 640, minW = 660, minH = 440 }, frame)
  if open then r.defer(loop) end
end
r.defer(loop)
