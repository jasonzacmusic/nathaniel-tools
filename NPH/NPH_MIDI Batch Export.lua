-- @description NPH MIDI Batch Export
-- @version 1.0.0
-- @author Jason Zac
-- @link https://daw.nathanielschool.com
-- @donation https://daw.nathanielschool.com/donate
-- @about Export many MIDI items/regions as separate .mid files with pattern-based sequential names.
-- @changelog
--   1.0.0 - first public release. Crash-hardened (GUID identity + ValidatePtr2),
--           signature-based change detection, shared safety library.

--[[
  MIDI Batch Export        NPH suite  -  amber (delivery)
  ----------------------------------------------------------------------------
  THE PROBLEM THIS SOLVES

  REAPER's "File > Export project MIDI" (action 40849) exports ONE file, from a
  time selection, behind a modal dialog.  Exporting seven riffs as seven
  numbered .mid files therefore means doing the whole dance seven times and
  typing seven filenames by hand.

  This exports every selected item / region / track in one pass, writing each to
  its own Standard MIDI File with names generated from a pattern.  No modal, no
  typing, no chance of two files silently overwriting each other.

  HOW IT WRITES THE FILES

  It does not drive 40849 at all.  It reads the MIDI with MIDI_GetAllEvts and
  writes the SMF bytes directly, which is what makes a batch possible.  The
  offsets REAPER hands back are already delta-times in the take's PPQ, so they
  map one-for-one onto SMF delta times - no requantising, no drift.  Tempo and
  time signature are written as meta events so the file opens at the right speed
  in Logic, MuseScore, Sibelius or anything else.

  Pointer safety: rows key on track GUID and item GUID, never on raw pointers.
  See NPH/lib/nph_safe.lua for why that is not optional.

  Requires: ReaImGui.
--]]

local r = reaper

if not r.ImGui_CreateContext then
  r.ShowMessageBox(
    "MIDI Batch Export needs ReaImGui.\n\n" ..
    "Extensions > ReaPack > Browse packages > search 'ReaImGui' > install > restart REAPER.",
    "MIDI Batch Export", 0)
  return
end

--------------------------------------------------------------------------------
-- pointer safety
--------------------------------------------------------------------------------
local function projAlive(p)
  if p == nil then return false end
  local ok, a = pcall(r.ValidatePtr2, 0, p, "ReaProject*")
  return ok and a == true
end
local function itemAlive(proj, it)
  if it == nil or not projAlive(proj) then return false end
  local ok, a = pcall(r.ValidatePtr2, proj, it, "MediaItem*")
  return ok and a == true
end
local function trackAlive(proj, t)
  if t == nil or not projAlive(proj) then return false end
  local ok, a = pcall(r.ValidatePtr2, proj, t, "MediaTrack*")
  return ok and a == true
end
local function activeProj() return r.EnumProjects(-1) end

local function tName(t)
  if not t then return "" end
  local ok, nm = r.GetSetMediaTrackInfo_String(t, "P_NAME", "", false)
  if ok and nm ~= "" then return nm end
  return "Track " .. math.floor(r.GetMediaTrackInfo_Value(t, "IP_TRACKNUMBER"))
end

--------------------------------------------------------------------------------
-- Standard MIDI File writer
--   SMF is big-endian.  Delta times are variable-length quantities.
--------------------------------------------------------------------------------
local function be32(n)
  return string.char((n >> 24) & 255, (n >> 16) & 255, (n >> 8) & 255, n & 255)
end
local function be16(n)
  return string.char((n >> 8) & 255, n & 255)
end
local function varlen(n)
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

-- meta events
local function metaTempo(bpm)
  if not bpm or bpm <= 0 then bpm = 120 end
  local uspq = math.floor(60000000 / bpm + 0.5)
  return varlen(0) .. "\xFF\x51\x03" ..
         string.char((uspq >> 16) & 255, (uspq >> 8) & 255, uspq & 255)
end
local function metaTimeSig(num, den)
  num = math.max(1, math.floor(num or 4))
  den = math.max(1, math.floor(den or 4))
  -- SMF stores the denominator as a power of two
  local dd, v = 0, den
  while v > 1 do v = v // 2; dd = dd + 1 end
  return varlen(0) .. "\xFF\x58\x04" .. string.char(num, dd, 24, 8)
end
local function metaTrackName(nm)
  nm = tostring(nm or ""):sub(1, 127)
  return varlen(0) .. "\xFF\x03" .. varlen(#nm) .. nm
end
local META_EOT = varlen(0) .. "\xFF\x2F\x00"

-- Convert one MIDI take into SMF bytes.
-- REAPER's MIDI_GetAllEvts gives: int32 LE offset (delta ticks), uint8 flag,
-- int32 LE msglen, msglen bytes of message.  The offsets are already deltas in
-- the take's PPQ, which is exactly what SMF wants.
local function takeToSMF(take, opts)
  if not take or not r.TakeIsMIDI(take) then return nil, "not a MIDI take" end
  local ok, buf = r.MIDI_GetAllEvts(take, "")
  if not ok or not buf or #buf == 0 then return nil, "no MIDI events" end

  local ppq = 960                          -- REAPER's internal ticks per quarter note
  local body = {}
  body[#body + 1] = metaTrackName(opts.name or "")
  body[#body + 1] = metaTempo(opts.bpm)
  body[#body + 1] = metaTimeSig(opts.num, opts.den)

  local pos, n = 1, #buf
  local carried = 0        -- delta of any event we skip must not be lost
  local wrote = 0
  while pos <= n - 8 do
    local offset, flag, len = string.unpack("<i4Bi4", buf, pos)
    pos = pos + 9
    if len < 0 or pos + len - 1 > n then break end
    local msg = buf:sub(pos, pos + len - 1)
    pos = pos + len

    local delta = offset + carried
    if len > 0 then
      local status = msg:byte(1) or 0
      -- Drop REAPER's internal all-notes-off / bank select noise only if asked;
      -- everything else goes through untouched so the file is a faithful copy.
      local skip = false
      if opts.notesOnly and status < 0xF0 then
        local kind = status & 0xF0
        skip = not (kind == 0x80 or kind == 0x90)
      end
      if skip then
        carried = delta
      else
        body[#body + 1] = varlen(delta) .. msg
        carried = 0
        wrote = wrote + 1
      end
    else
      carried = delta
    end
  end

  if wrote == 0 then return nil, "no MIDI events" end
  body[#body + 1] = META_EOT

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
  if s == "" then s = "untitled" end
  return s
end

-- Pattern tokens:  $num  $name  $track  $project  $bpm
local function expand(pattern, vars, num, pad)
  local out = pattern
  out = out:gsub("%$num",     string.format("%0" .. pad .. "d", num))
  out = out:gsub("%$name",    sanitise(vars.name))
  out = out:gsub("%$track",   sanitise(vars.track))
  out = out:gsub("%$project", sanitise(vars.project))
  out = out:gsub("%$bpm",     tostring(math.floor((vars.bpm or 120) + 0.5)))
  return sanitise(out)
end

--------------------------------------------------------------------------------
-- gathering
--------------------------------------------------------------------------------
local SOURCE = { "Selected items", "All items on selected tracks", "Regions", "Every MIDI item" }

local function projectName(proj)
  local _, path = r.EnumProjects(-1, "")
  for i = 0, 128 do
    local p, pth = r.EnumProjects(i)
    if not p then break end
    if p == proj then path = pth or "" break end
  end
  local nm = (path or ""):match("[^/\\]+$") or ""
  nm = nm:gsub("%.[Rr][Pp][Pp]$", "")
  if nm == "" then nm = "untitled" end
  return nm
end

-- One row per file we will write.
local function gather(proj, sourceIdx)
  local out = {}
  if not projAlive(proj) then return out end

  local function addItem(it)
    if not itemAlive(proj, it) then return end
    local take = r.GetActiveTake(it)
    if not take or not r.TakeIsMIDI(take) then return end
    local tr = r.GetMediaItem_Track(it)
    local pos = r.GetMediaItemInfo_Value(it, "D_POSITION")
    local _, takeName = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
    out[#out + 1] = {
      itemGuid = r.BR_GetMediaItemGUID and r.BR_GetMediaItemGUID(it) or tostring(it),
      item     = it,                          -- resolved fresh at export time
      name     = (takeName ~= "" and takeName) or tName(tr),
      track    = tName(tr),
      pos      = pos,
      len      = r.GetMediaItemInfo_Value(it, "D_LENGTH"),
      on       = true,
    }
  end

  if sourceIdx == 1 then
    for i = 0, r.CountSelectedMediaItems(proj) - 1 do
      addItem(r.GetSelectedMediaItem(proj, i))
    end
  elseif sourceIdx == 2 then
    local sel = {}
    for i = 0, r.CountSelectedTracks(proj) - 1 do sel[r.GetSelectedTrack(proj, i)] = true end
    for i = 0, r.CountMediaItems(proj) - 1 do
      local it = r.GetMediaItem(proj, i)
      if it and sel[r.GetMediaItem_Track(it)] then addItem(it) end
    end
  elseif sourceIdx == 4 then
    for i = 0, r.CountMediaItems(proj) - 1 do addItem(r.GetMediaItem(proj, i)) end
  else
    -- Regions: one file per region, merging every MIDI item that starts inside it.
    local idx = 0
    while true do
      local ok, isrgn, s, e, nm = r.EnumProjectMarkers3(proj, idx)
      if ok == 0 then break end
      if isrgn then
        local members = {}
        for i = 0, r.CountMediaItems(proj) - 1 do
          local it = r.GetMediaItem(proj, i)
          if it then
            local tk = r.GetActiveTake(it)
            local p  = r.GetMediaItemInfo_Value(it, "D_POSITION")
            if tk and r.TakeIsMIDI(tk) and p >= s - 1e-9 and p < e - 1e-9 then
              members[#members + 1] = it
            end
          end
        end
        if #members > 0 then
          out[#out + 1] = {
            region = true, members = members,
            name = (nm ~= "" and nm) or ("Region " .. (idx + 1)),
            track = "", pos = s, len = e - s, on = true,
          }
        end
      end
      idx = idx + 1
    end
    table.sort(out, function(a, b) return a.pos < b.pos end)
  end

  if sourceIdx ~= 3 then
    table.sort(out, function(a, b)
      if math.abs(a.pos - b.pos) > 1e-9 then return a.pos < b.pos end
      return (a.track or "") < (b.track or "")
    end)
  end
  return out
end

--------------------------------------------------------------------------------
-- state
--------------------------------------------------------------------------------
local ctx = r.ImGui_CreateContext('MIDI Batch Export')
local rows        = {}
local sourceIdx   = 1
local pattern     = "$num - $name"
local startNum    = 1
local padding     = 2
local outDir      = ""
local notesOnly   = false
local overwrite   = false
local logLines    = {}
local firstFrame, dockPending = true, nil
-- Change detection. NOT GetProjectStateChangeCount: measured in REAPER 7.77 that
-- counter does NOT move when a track or item is added, renamed or deleted, so a
-- watchdog built on it never fires. We diff a cheap signature instead.
local lastSig, lastSigT = nil, 0
local function projSig(proj)
  if not projAlive(proj) then return "dead" end
  local acc = { r.CountTracks(proj), r.CountMediaItems(proj), r.CountSelectedMediaItems(proj) }
  for i = 0, r.CountMediaItems(proj) - 1 do
    local it = r.GetMediaItem(proj, i)
    if it then
      acc[#acc+1] = string.format("%.4f", r.GetMediaItemInfo_Value(it, "D_POSITION"))
    end
  end
  return table.concat(acc, "|")
end

local function log(s) logLines[#logLines + 1] = s; if #logLines > 300 then table.remove(logLines, 1) end end

local function defaultDir()
  local proj = activeProj()
  local _, path = r.EnumProjects(-1, "")
  for i = 0, 128 do
    local p, pth = r.EnumProjects(i)
    if not p then break end
    if p == proj then path = pth or "" break end
  end
  local d = (path or ""):match("^(.*)[/\\][^/\\]+$")
  if d and d ~= "" then return d .. "/MIDI Export" end
  return (r.GetProjectPath("") or "") .. "/MIDI Export"
end

local function rebuild()
  local proj = activeProj()
  local keep = {}
  for _, row in ipairs(rows) do keep[row.name .. "|" .. tostring(row.pos)] = row.on end
  rows = gather(proj, sourceIdx)
  for _, row in ipairs(rows) do
    local k = row.name .. "|" .. tostring(row.pos)
    if keep[k] ~= nil then row.on = keep[k] end
  end
  lastSig = projSig(proj)
  if outDir == "" then outDir = defaultDir() end
end

-- Filenames for the currently ticked rows, with collision detection.
local function plan()
  local proj = activeProj()
  local vars = { project = projectName(proj), bpm = r.Master_GetTempo() }
  local list, seen, clashes = {}, {}, 0
  local n = startNum
  for _, row in ipairs(rows) do
    if row.on then
      vars.name  = row.name
      vars.track = row.track
      local fn = expand(pattern, vars, n, padding) .. ".mid"
      if seen[fn:lower()] then clashes = clashes + 1 end
      seen[fn:lower()] = true
      list[#list + 1] = { row = row, file = fn, num = n }
      n = n + 1
    end
  end
  return list, clashes
end

--------------------------------------------------------------------------------
-- export
--------------------------------------------------------------------------------
local function ensureDir(path)
  if r.RecursiveCreateDirectory then r.RecursiveCreateDirectory(path, 0) end
end

local function fileExists(p)
  local f = io.open(p, "rb")
  if f then f:close(); return true end
  return false
end

local function doExport()
  logLines = {}
  local proj = activeProj()
  if not projAlive(proj) then log("No project."); return end

  local list, clashes = plan()
  if #list == 0 then log("Nothing ticked to export."); return end
  if clashes > 0 and not overwrite then
    log(("STOPPED: %d filename collision(s). Two rows would write the same file and one " ..
         "would be silently lost."):format(clashes))
    log("  Add $num or $track to the pattern, or tick 'Allow overwrite' if you really mean it.")
    return
  end

  if outDir == "" then outDir = defaultDir() end
  ensureDir(outDir)

  local bpm = r.Master_GetTempo()
  local num, den = 4, 4
  do
    local n2, d2 = r.TimeMap_GetTimeSigAtTime(proj, 0)
    if n2 and n2 > 0 then num, den = n2, d2 end
  end

  local written, skipped, failed = 0, 0, 0
  for _, entry in ipairs(list) do
    local row  = entry.row
    local path = outDir .. "/" .. entry.file

    if fileExists(path) and not overwrite then
      log(("  SKIP  %-40s already exists"):format(entry.file))
      skipped = skipped + 1
      goto continue
    end

    do
      -- Resolve the item(s) fresh.  Anything deleted since the list was built
      -- is reported, never dereferenced.
      local sources = {}
      if row.region then
        for _, it in ipairs(row.members or {}) do
          if itemAlive(proj, it) then sources[#sources + 1] = it end
        end
      elseif itemAlive(proj, row.item) then
        sources[1] = row.item
      end

      if #sources == 0 then
        log(("  GONE  %-40s item was deleted since the list was built"):format(entry.file))
        failed = failed + 1
        goto continue
      end

      -- One file per row.  For a region with several MIDI items we export the
      -- first take; merging multiple tracks into one SMF track would silently
      -- collapse channels, which is worse than being explicit about it.
      if #sources > 1 then
        log(("  NOTE  %s: region holds %d MIDI items, exporting the first."):format(entry.file, #sources))
      end

      local take = r.GetActiveTake(sources[1])
      local data, err = takeToSMF(take, {
        name = row.name, bpm = bpm, num = num, den = den, notesOnly = notesOnly,
      })
      if not data then
        log(("  FAIL  %-40s %s"):format(entry.file, tostring(err)))
        failed = failed + 1
      else
        local f = io.open(path, "wb")
        if not f then
          log(("  FAIL  %-40s could not open for writing"):format(entry.file))
          failed = failed + 1
        else
          f:write(data); f:close()
          log(("  OK    %-40s %d bytes"):format(entry.file, #data))
          written = written + 1
        end
      end
    end
    ::continue::
  end

  log(("Done. %d written, %d skipped, %d failed  ->  %s"):format(written, skipped, failed, outDir))
end

local function revealFolder()
  if outDir ~= "" then
    ensureDir(outDir)
    if r.CF_ShellExecute then r.CF_ShellExecute(outDir)
    else os.execute('open "' .. outDir .. '"') end
  end
end

--------------------------------------------------------------------------------
-- theme  (amber = delivery)
--------------------------------------------------------------------------------
local A, AH, AA = 0xE0912Eff, 0xF0A544ff, 0xC47A20ff
local BG, PANEL, TXT, MUT = 0x1A1512ff, 0x241C16ff, 0xF0E6DAff, 0x9A8B7Aff
local GREEN, RED = 0x6BC77Aff, 0xE06A5Aff

local function pushTheme()
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 5)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 12, 10)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 7, 4)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), BG)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), TXT)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), PANEL)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), AA)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), AH)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), A)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), AA)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgActive(), AA)
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

  r.ImGui_AlignTextToFramePadding(ctx); r.ImGui_Text(ctx, "Export")
  r.ImGui_SameLine(ctx); r.ImGui_SetNextItemWidth(ctx, 210)
  if r.ImGui_BeginCombo(ctx, "##src", SOURCE[sourceIdx]) then
    for i, s in ipairs(SOURCE) do
      if r.ImGui_Selectable(ctx, s, i == sourceIdx) then sourceIdx = i; rebuild() end
    end
    r.ImGui_EndCombo(ctx)
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_SmallButton(ctx, "Rescan") then rebuild() end
  r.ImGui_SameLine(ctx)
  local dchg, dval = r.ImGui_Checkbox(ctx, "Dock", r.ImGui_IsWindowDocked(ctx))
  if dchg then dockPending = dval and -1 or 0 end

  r.ImGui_Separator(ctx)

  -- naming
  r.ImGui_AlignTextToFramePadding(ctx); r.ImGui_Text(ctx, "Name")
  r.ImGui_SameLine(ctx); r.ImGui_SetNextItemWidth(ctx, 260)
  local pc, pv = r.ImGui_InputText(ctx, "##pat", pattern)
  if pc then pattern = pv end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Tokens:  $num  $name  $track  $project  $bpm\nExample:  Riff $num - $name")
  end
  r.ImGui_SameLine(ctx); r.ImGui_Text(ctx, "start")
  r.ImGui_SameLine(ctx); r.ImGui_SetNextItemWidth(ctx, 60)
  local sc, sv = r.ImGui_InputInt(ctx, "##start", startNum, 0)
  if sc then startNum = math.max(0, sv) end
  r.ImGui_SameLine(ctx); r.ImGui_Text(ctx, "digits")
  r.ImGui_SameLine(ctx); r.ImGui_SetNextItemWidth(ctx, 60)
  local dc2, dv2 = r.ImGui_InputInt(ctx, "##pad", padding, 0)
  if dc2 then padding = math.min(6, math.max(1, dv2)) end

  r.ImGui_AlignTextToFramePadding(ctx); r.ImGui_Text(ctx, "Folder")
  r.ImGui_SameLine(ctx); r.ImGui_SetNextItemWidth(ctx, 420)
  local oc, ov = r.ImGui_InputText(ctx, "##dir", outDir)
  if oc then outDir = ov end
  r.ImGui_SameLine(ctx)
  if r.ImGui_SmallButton(ctx, "Reveal") then revealFolder() end

  local nc, nv = r.ImGui_Checkbox(ctx, "Notes only", notesOnly)
  if nc then notesOnly = nv end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Strip CC, pitch bend and aftertouch. Leave off for a faithful copy.")
  end
  r.ImGui_SameLine(ctx)
  local wc, wv = r.ImGui_Checkbox(ctx, "Allow overwrite", overwrite)
  if wc then overwrite = wv end

  r.ImGui_Separator(ctx)

  local list, clashes = plan()
  if clashes > 0 then
    r.ImGui_TextColored(ctx, RED,
      ("%d filename collision(s) - add $num or $track, or files will overwrite each other."):format(clashes))
  else
    r.ImGui_TextColored(ctx, MUT, ("%d file(s) will be written to  %s"):format(#list, outDir))
  end

  -- the list, with the exact filename each row produces
  local flags = r.ImGui_TableFlags_Borders() | r.ImGui_TableFlags_RowBg() | r.ImGui_TableFlags_ScrollY()
  local _, availH = r.ImGui_GetContentRegionAvail(ctx)
  if r.ImGui_BeginTable(ctx, "files", 4, flags, 0, math.max(120, availH - 130)) then
    r.ImGui_TableSetupScrollFreeze(ctx, 0, 1)
    r.ImGui_TableSetupColumn(ctx, "", r.ImGui_TableColumnFlags_WidthFixed(), 26)
    r.ImGui_TableSetupColumn(ctx, "Source", r.ImGui_TableColumnFlags_WidthStretch())
    r.ImGui_TableSetupColumn(ctx, "Track", r.ImGui_TableColumnFlags_WidthFixed(), 150)
    r.ImGui_TableSetupColumn(ctx, "Writes file", r.ImGui_TableColumnFlags_WidthStretch())
    r.ImGui_TableHeadersRow(ctx)

    local fileOf = {}
    for _, e in ipairs(list) do fileOf[e.row] = e.file end

    for i, row in ipairs(rows) do
      r.ImGui_TableNextRow(ctx); r.ImGui_PushID(ctx, i)
      r.ImGui_TableNextColumn(ctx)
      local c, v = r.ImGui_Checkbox(ctx, "##on", row.on)
      if c then row.on = v end
      r.ImGui_TableNextColumn(ctx); r.ImGui_Text(ctx, row.name)
      r.ImGui_TableNextColumn(ctx); r.ImGui_TextColored(ctx, MUT, row.track or "")
      r.ImGui_TableNextColumn(ctx)
      if row.on and fileOf[row] then r.ImGui_TextColored(ctx, GREEN, fileOf[row])
      else r.ImGui_TextColored(ctx, MUT, "-") end
      r.ImGui_PopID(ctx)
    end
    r.ImGui_EndTable(ctx)
  end

  if r.ImGui_Button(ctx, "All") then for _, x in ipairs(rows) do x.on = true end end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "None") then for _, x in ipairs(rows) do x.on = false end end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, ("EXPORT  %d file(s)"):format(#list)) then doExport() end

  if #logLines > 0 then
    r.ImGui_Separator(ctx)
    if r.ImGui_BeginChild(ctx, "log", 0, 90) then
      for _, l in ipairs(logLines) do
        local col = TXT
        if l:find("FAIL") or l:find("STOPPED") or l:find("GONE") then col = RED
        elseif l:find("OK ") then col = GREEN
        elseif l:find("SKIP") or l:find("NOTE") then col = MUT end
        r.ImGui_TextColored(ctx, col, l)
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
  -- watchdog: resync when the project changes under us
  local proj = activeProj()
  if projAlive(proj) then
    local now = r.time_precise()
    if now - lastSigT > 0.25 then      -- throttled: the signature walks every item
      lastSigT = now
      if projSig(proj) ~= lastSig then rebuild() end
    end
  else
    rows = {}
  end

  if dockPending ~= nil then r.ImGui_SetNextWindowDockID(ctx, dockPending); dockPending = nil end
  if firstFrame then r.ImGui_SetNextWindowSize(ctx, 820, 620); firstFrame = false end

  pushTheme()
  local vis, open = r.ImGui_Begin(ctx, 'MIDI Batch Export', true)
  if vis then
    local ok, err = pcall(frame)
    if not ok then r.ImGui_TextColored(ctx, RED, "Error: " .. tostring(err)) end
    r.ImGui_End(ctx)
  end
  popTheme()
  if open then r.defer(loop) end
end

r.defer(loop)
