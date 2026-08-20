-- @description Click Strip
-- @version 1.0.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about
--   The click, on one wide bar you can grab.
--
--   Metronome on/off, pre-roll on/off and its bar count, and both beat volumes
--   as long drag bars with the dB written on them. Drag anywhere along a bar -
--   you do not have to find a tiny handle. Double-click a bar to put it back to
--   a sensible level.
--
--   This replaces reaching for the settings cog every time the click is too
--   loud. The cog is still here, at the end, for the things that genuinely
--   belong in a dialog (sounds, pattern, time signature).
--
--   Requires the "Shared Libraries" package from this same repository
--   (right-click the repository in ReaPack > Install All).
-- @changelog
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
  r.ShowMessageBox("Click Strip needs the 'Shared Libraries' package.\n\nExtensions > ReaPack > Browse packages > Nathaniel Tools > Shared Libraries > Install (or Install All).", "Click Strip", 0)
  return
end
do local ok, compat = pcall(require, "nt_imgui"); if ok then compat.install() end end
if not safe.require("Click Strip", { imgui = true }) then return end

if type(r.SNM_GetDoubleConfigVar) ~= "function" then
  r.ShowMessageBox("Click Strip needs the SWS extension.\n\nInstall SWS, then restart REAPER.", "Click Strip", 0)
  return
end

local APP = "Click Strip"
local T = ui.tokens
local ACCENT = ui.accents.amber
local ctx = r.ImGui_CreateContext(APP)
ui.fonts(ctx)

--------------------------------------------------------------------------------
-- REAPER state
--------------------------------------------------------------------------------
local METRONOME   = 40364  -- Options: Toggle metronome
local PREROLL     = 41819  -- Pre-roll: Toggle pre-roll on record
local SETTINGS    = 40363  -- Options: Show metronome/pre-roll settings
local COUNT_IN    = 40045  -- Options: Toggle metronome count-in on record

local MIN_DB, MAX_DB = -60.0, 6.0
local DEFAULT_DB = { -12.0, -20.0 }   -- a click you can hear under a band, not over it

local function gainToDb(gain)
  if gain <= 0.0000001 then return MIN_DB end
  return 20 * math.log(gain, 10)
end
local function dbToGain(db)
  if db <= MIN_DB then return 0 end
  return 10 ^ (db / 20)
end
local function clampDb(db) return math.max(MIN_DB, math.min(MAX_DB, db)) end

-- Fader taper. A straight dB scale would spend half the bar below -27 dB,
-- where nothing useful lives. Squaring it puts the -24..+6 dB region - the only
-- part you actually set a click in - across most of the travel, so the bar
-- feels like a fader instead of a switch.
local function positionToDb(position)
  position = math.max(0, math.min(1, position))
  return clampDb(MAX_DB - ((1 - position) ^ 2) * (MAX_DB - MIN_DB))
end
local function dbToPosition(db)
  local span = (MAX_DB - clampDb(db)) / (MAX_DB - MIN_DB)
  return math.max(0, math.min(1, 1 - math.sqrt(span)))
end

local function readDb(key, fallback)
  return clampDb(gainToDb(r.SNM_GetDoubleConfigVar(key, dbToGain(fallback))))
end
local function writeDb(key, db)
  r.SNM_SetDoubleConfigVar(key, dbToGain(clampDb(db)))
end

local function isOn(command) return r.GetToggleCommandState(command) == 1 end
local function fire(command) r.Main_OnCommand(command, 0) end

local function prerollBars()
  return math.max(1, math.floor(r.SNM_GetDoubleConfigVar("prerollmeas", 2) + 0.5))
end
local function setPrerollBars(n)
  r.SNM_SetDoubleConfigVar("prerollmeas", math.max(1, math.min(32, n)))
end


--------------------------------------------------------------------------------
-- time signature + accents
--------------------------------------------------------------------------------
-- REAPER packs the click pattern into one number: two bits per beat, first beat
-- in the lowest bits, 1 = accented beat, 2 = ordinary beat. Verified against
-- Jason's own settings, where the pattern "ABBB" is stored as 169.
local function encodePattern(chars)
  local low, high = 0, 0
  for i, ch in ipairs(chars) do
    local value = (ch == "A") and 1 or 2
    local shift = 2 * (i - 1)
    if shift < 32 then low = low | (value << shift)
    else high = high | (value << (shift - 32)) end
  end
  -- config vars are signed 32-bit
  if low  >= 0x80000000 then low  = low  - 0x100000000 end
  if high >= 0x80000000 then high = high - 0x100000000 end
  return low, high
end

-- {7, 6} -> "ABBBBBB" .. "ABBBBB": one accent at the head of each group.
local function patternChars(groups)
  local chars = {}
  for _, count in ipairs(groups) do
    for beat = 1, count do chars[#chars + 1] = (beat == 1) and "A" or "B" end
  end
  return chars
end

-- REAPER does not expose the click's accent pattern to scripts - it is not in
-- the config vars SWS can reach (checked live: projmetropattern reads back as
-- "not available" while projmetrov1 reads fine). So the meter buttons set the
-- time signature, which REAPER does allow, and hand back the pattern to type
-- once into the click settings behind MORE.
local function accentPattern(groups)
  return table.concat(patternChars(groups))
end

-- Put the time signature on the bar the cursor is sitting in, which is what a
-- musician means by "make this 7/8".
local function applyMeter(num, den)
  local pos = r.GetCursorPosition()
  local _, measures = r.TimeMap2_timeToBeats(0, pos)
  local measureStart = r.TimeMap2_beatsToTime(0, 0, measures)
  local bpm = r.TimeMap2_GetDividedBpmAtTime(0, measureStart)
  if not bpm or bpm <= 0 then bpm = r.Master_GetTempo() end

  local existing = r.FindTempoTimeSigMarker(0, measureStart + 0.0001)
  local done = false
  if existing and existing >= 0 then
    local ok, markerPos = r.GetTempoTimeSigMarker(0, existing)
    if ok and math.abs(markerPos - measureStart) < 0.001 then
      done = r.SetTempoTimeSigMarker(0, existing, -1, measures, 0, bpm, num, den, false)
    end
  end
  if not done then
    done = r.SetTempoTimeSigMarker(0, -1, -1, measures, 0, bpm, num, den, false)
  end
  r.UpdateTimeline()
  return done
end

local function setMeter(groups, den, label)
  local total = 0
  for _, count in ipairs(groups) do total = total + count end
  if total < 1 then return end
  r.Undo_BeginBlock()
  applyMeter(total, den)
  local pattern = accentPattern(groups)
  r.Undo_EndBlock("Set meter " .. total .. "/" .. den, -1)
  return pattern
end

-- "7+6" -> {7,6} · "3+3+2" -> {3,3,2} · "13" -> {13} · "7+6/8" -> {7,6} over 8
local function parseGroups(text)
  local body, den = text:match("^(.-)%s*/%s*(%d+)%s*$")
  body = body or text
  den = tonumber(den) or 8
  local groups = {}
  for piece in body:gmatch("[^%+%s]+") do
    local n = tonumber(piece)
    if n and n >= 1 then groups[#groups + 1] = math.floor(n) end
  end
  if #groups == 0 then return nil, nil end
  return groups, den
end

-- His six, plus the grouping each one is normally felt in.
local PRESETS = {
  { label = "4/4",  groups = { 4 },       den = 4 },
  { label = "3/4",  groups = { 3 },       den = 4 },
  { label = "6/8",  groups = { 3, 3 },    den = 8 },
  { label = "5/8",  groups = { 3, 2 },    den = 8 },
  { label = "8/8",  groups = { 3, 3, 2 }, den = 8 },
  { label = "9/8",  groups = { 3, 3, 3 }, den = 8 },
}

local oddText = "7+6"
local lastPattern = ""

--------------------------------------------------------------------------------
-- the drag bar
--------------------------------------------------------------------------------
-- A long horizontal bar you can grab anywhere. No handle to hunt for: press
-- down at any point and the level jumps there, then follows the mouse.
local function dragBar(id, label, db, width, height)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_InvisibleButton(ctx, id, width, height)

  local hovered = r.ImGui_IsItemHovered(ctx)
  local active  = r.ImGui_IsItemActive(ctx)
  local newDb = db

  if active then
    local mx = r.ImGui_GetMousePos(ctx)
    newDb = positionToDb((mx - x) / math.max(1, width))
  end
  if hovered and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
    newDb = nil   -- caller resets to its default
  end

  local shown = newDb or db
  local fill = dbToPosition(shown)

  -- track
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + width, y + height, T.panel, 6)
  -- filled portion
  local barColour = active and ui.shade(ACCENT, 0.15) or (hovered and ui.shade(ACCENT, 0.06) or ACCENT)
  if fill > 0 then
    r.ImGui_DrawList_AddRectFilled(dl, x, y, x + width * fill, y + height, barColour, 6)
  end
  -- unity mark at 0 dB so the useful spot is findable by eye
  local zero = dbToPosition(0)
  r.ImGui_DrawList_AddRectFilled(dl, x + width * zero - 1, y + 3, x + width * zero + 1, y + height - 3, ui.alpha(T.white, 0.28))
  r.ImGui_DrawList_AddRect(dl, x, y, x + width, y + height, T.border, 6)

  -- label on the left of the bar, value on the right, both inside it
  ui.pushFont(ctx, "small", true)
  r.ImGui_DrawList_AddText(dl, x + 10, y + height / 2 - 7, ui.alpha(T.white, 0.92), label)
  local value = (shown <= MIN_DB) and "off" or string.format("%.1f dB", shown)
  local tw = r.ImGui_CalcTextSize(ctx, value)
  r.ImGui_DrawList_AddText(dl, x + width - tw - 10, y + height / 2 - 7, ui.alpha(T.white, 0.92), value)
  ui.popFont(ctx)

  return newDb, (newDb == nil)
end


--------------------------------------------------------------------------------
-- the Korg
--------------------------------------------------------------------------------
-- 12 Step Bridge leaves the nanoKONTROL's click moves in one small file. Its
-- profile is untouched: Fader 1 is still the downbeat, Knob 1 the other beats,
-- Mute 1 the click, Solo 1 the pre-roll. This is only the last few inches -
-- REAPER has no action those controls could be learned to, because the beat
-- levels are config values only a script inside REAPER can set.
local MAILBOX = r.GetResourcePath() .. "/nt_click_mailbox.txt"
local lastMailSequence = nil
local korgSeen = 0

local function readMailbox()
  local fh = io.open(MAILBOX, "r")
  if not fh then return end
  local line = fh:read("*l")
  fh:close()
  if not line then return end
  local sequence, key, value = line:match("^(%d+)%s+(%S+)%s+(%S+)$")
  if not sequence then return end
  if sequence == lastMailSequence then return end
  lastMailSequence = sequence

  korgSeen = r.time_precise()
  if key == "beat1gain" or key == "beat2gain" then
    -- exact gain, used to put a level back precisely
    local gain = tonumber(value)
    if gain then r.SNM_SetDoubleConfigVar(key == "beat1gain" and "projmetrov1" or "projmetrov2", gain) end
  elseif key == "beat1" or key == "beat2" then
    local cc = tonumber(value)
    if cc then
      writeDb(key == "beat1" and "projmetrov1" or "projmetrov2", positionToDb(cc / 127))
    end
  elseif key == "metronome" then fire(METRONOME)
  elseif key == "preroll" then fire(PREROLL)
  elseif key == "settings" then fire(SETTINGS)
  end
end

--------------------------------------------------------------------------------
-- frame
--------------------------------------------------------------------------------
-- nt_ui's error net records the message for a status line, and a one-line strip
-- has no status line - so a broken frame would show as an empty black bar and
-- look like nothing happened. Say it out loud instead, on screen and in a log.
local reportedError = nil
local function reportError(err)
  if reportedError == err then return end
  reportedError = err
  local fh = io.open(r.GetResourcePath() .. "/nt_click_strip_error.log", "a")
  if fh then fh:write(os.date("%Y-%m-%d %H:%M:%S ") .. tostring(err) .. "\n"); fh:close() end
end

local reportedSize = false
local function drawFrame()
  readMailbox()
  local metro   = isOn(METRONOME)
  local preroll = isOn(PREROLL)
  local countIn = isOn(COUNT_IN)

  local avail, availH = r.ImGui_GetContentRegionAvail(ctx)
  avail = avail or 0
  if not reportedSize then
    reportedSize = true
    local fh = io.open(r.GetResourcePath() .. "/nt_click_strip_error.log", "a")
    if fh then
      fh:write(os.date("%Y-%m-%d %H:%M:%S ") .. string.format("first frame, content region %.0f x %.0f\n", avail, availH or 0))
      fh:close()
    end
  end
  local narrow = avail < 900

  -- ---- switches -----------------------------------------------------------
  if ui.button(ctx, metro and "CLICK ON" or "CLICK OFF", {
    kind = metro and "primary" or "secondary", colour = ACCENT, w = narrow and 120 or 150, h = 40,
    tip = "The metronome. Same as REAPER's own metronome button."
  }) then fire(METRONOME) end

  r.ImGui_SameLine(ctx)
  if ui.button(ctx, preroll and "PRE-ROLL ON" or "PRE-ROLL OFF", {
    kind = preroll and "primary" or "secondary", colour = ACCENT, w = narrow and 130 or 165, h = 40,
    tip = "Count you in before recording actually starts."
  }) then fire(PREROLL) end

  r.ImGui_SameLine(ctx)
  local bars = prerollBars()
  if ui.button(ctx, "-", { w = 34, h = 40, tip = "One bar less of pre-roll." }) then setPrerollBars(bars - 1) end
  r.ImGui_SameLine(ctx)
  ui.pushFont(ctx, "title", true)
  r.ImGui_Text(ctx, string.format("%d", bars))
  ui.popFont(ctx)
  r.ImGui_SameLine(ctx)
  ui.dim(ctx, bars == 1 and "bar" or "bars")
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "+", { w = 34, h = 40, tip = "One bar more of pre-roll." }) then setPrerollBars(bars + 1) end

  r.ImGui_SameLine(ctx)
  if ui.button(ctx, countIn and "COUNT-IN ON" or "COUNT-IN OFF", {
    kind = countIn and "primary" or "secondary", colour = ACCENT, w = narrow and 130 or 160, h = 40,
    tip = "Click through the pre-roll bars before recording."
  }) then fire(COUNT_IN) end

  -- ---- the two drag bars --------------------------------------------------
  if narrow then
    r.ImGui_Dummy(ctx, 1, 8)
  else
    r.ImGui_SameLine(ctx)
    r.ImGui_Dummy(ctx, 18, 1)
    r.ImGui_SameLine(ctx)
  end

  -- Whatever room is left goes to the bars: on a wide screen they are long
  -- enough to set a level precisely without a dialog.
  local remaining = r.ImGui_GetContentRegionAvail(ctx)
  local cogWidth = 62
  local barWidth = math.max(180, (remaining - cogWidth - 30) / 2)

  local db1 = readDb("projmetrov1", DEFAULT_DB[1])
  local newDb1, reset1 = dragBar("##beat1", "BEAT 1", db1, barWidth, 40)
  if reset1 then writeDb("projmetrov1", DEFAULT_DB[1])
  elseif newDb1 and math.abs(newDb1 - db1) > 0.01 then writeDb("projmetrov1", newDb1) end
  ui.tip(ctx, "How loud the downbeat is. Drag anywhere along the bar; double-click to reset.")

  r.ImGui_SameLine(ctx)
  local db2 = readDb("projmetrov2", DEFAULT_DB[2])
  local newDb2, reset2 = dragBar("##beat2", "OTHER BEATS", db2, barWidth, 40)
  if reset2 then writeDb("projmetrov2", DEFAULT_DB[2])
  elseif newDb2 and math.abs(newDb2 - db2) > 0.01 then writeDb("projmetrov2", newDb2) end
  ui.tip(ctx, "How loud beats 2, 3 and 4 are. Drag anywhere along the bar; double-click to reset.")

  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "MORE", { kind = "ghost", w = cogWidth, h = 40,
    tip = "The rest of the click settings: sounds, pattern, time signature." }) then
    fire(SETTINGS)
  end

  -- ---- meter --------------------------------------------------------------
  r.ImGui_Dummy(ctx, 1, 6)
  ui.dim(ctx, "METER")
  r.ImGui_SameLine(ctx)
  r.ImGui_Dummy(ctx, 8, 1)

  for _, preset in ipairs(PRESETS) do
    r.ImGui_SameLine(ctx)
    if ui.button(ctx, preset.label, { w = 54, h = 32,
      tip = "Set the bar the cursor is in to " .. preset.label .. ", and accent it " ..
            table.concat(preset.groups, "+") .. "." }) then
      lastPattern = setMeter(preset.groups, preset.den, preset.label) or ""
    end
  end

  r.ImGui_SameLine(ctx)
  r.ImGui_Dummy(ctx, 16, 1)
  r.ImGui_SameLine(ctx)
  ui.dim(ctx, "ODD")
  r.ImGui_SameLine(ctx)
  r.ImGui_SetNextItemWidth(ctx, 120)
  local changed, typed = r.ImGui_InputText(ctx, "##odd", oddText)
  if changed then oddText = typed end
  ui.tip(ctx, "Type the groups you feel, like 7+6 or 3+3+2. Add /4 or /8 to say what the beat is; 8 if you leave it out.")

  local groups, den = parseGroups(oddText)
  local total = 0
  if groups then for _, count in ipairs(groups) do total = total + count end end

  r.ImGui_SameLine(ctx)
  if ui.button(ctx, groups and string.format("SET %d/%d", total, den) or "SET", {
    kind = "primary", colour = ACCENT, w = 96, h = 32, disabled = groups == nil,
    tip = groups and ("Sets the bar to " .. total .. "/" .. den .. ", accented " ..
          table.concat(groups, "+") .. ".") or "Type something like 7+6 first."
  }) then
    lastPattern = setMeter(groups, den, oddText) or ""
  end

  if korgSeen > 0 and (r.time_precise() - korgSeen) < 1.5 then
    r.ImGui_SameLine(ctx)
    r.ImGui_TextColored(ctx, ACCENT, "KORG")
  end

  if lastPattern ~= "" then
    r.ImGui_SameLine(ctx)
    r.ImGui_Dummy(ctx, 10, 1)
    r.ImGui_SameLine(ctx)
    ui.dim(ctx, "click: " .. lastPattern:gsub("A", "1 "):gsub("B", ". "))
  end
end

local function frame()
  local ok, err = pcall(drawFrame)
  if not ok then
    reportError(err)
    r.ImGui_TextColored(ctx, T.danger, "Click Strip hit an error: " .. tostring(err))
  end
end

--------------------------------------------------------------------------------
-- A one-line strip is no use as the eighth tab of a docker, behind the mixer:
-- you would never see the click level you came to change. It lives across the
-- top of the screen instead, under the menu bar, where the toolbars are.
if r.GetExtState("NT_UI", "clickstrip_placed") ~= "3" then
  r.SetExtState("NT_UI", "clickstrip_placed", "3", true)
  r.SetExtState("NT_UI", "dock:Click Strip", "0", true)
  r.SetExtState("NT_UI", "clickstrip_reposition", "1", false)
end

local STRIP_HEIGHT = 146

-- Full width of the display, pinned to the top. Falls back to his REAPER
-- window's width if the viewport API is missing.
local function topOfScreen()
  local x, y, w = 0, 38, 2557
  if r.ImGui_GetMainViewport and r.ImGui_Viewport_GetWorkPos then
    local vp = r.ImGui_GetMainViewport(ctx)
    local vx, vy = r.ImGui_Viewport_GetWorkPos(vp)
    local vw = r.ImGui_Viewport_GetWorkSize(vp)
    if vx and vw and vw > 400 then x, y, w = vx, vy, vw end
  end
  return x, y, w
end

local placeFrames = (r.GetExtState("NT_UI", "clickstrip_reposition") == "1") and 4 or 0
if placeFrames > 0 then r.DeleteExtState("NT_UI", "clickstrip_reposition", false) end

-- Running the action brings the strip to the front rather than leaving it
-- behind whatever was there.
local focusFrames = 3
local function loop()
  if focusFrames > 0 then
    focusFrames = focusFrames - 1
    if r.ImGui_SetNextWindowFocus then r.ImGui_SetNextWindowFocus(ctx) end
  end
  if placeFrames > 0 then
    placeFrames = placeFrames - 1
    local x, y, w = topOfScreen()
    local always = r.ImGui_Cond_Always and r.ImGui_Cond_Always() or 1
    if r.ImGui_SetNextWindowPos then r.ImGui_SetNextWindowPos(ctx, x, y, always) end
    if r.ImGui_SetNextWindowSize then r.ImGui_SetNextWindowSize(ctx, w, STRIP_HEIGHT, always) end
  end
  local open = ui.window(ctx, {
    title = APP,
    accent = ACCENT,
    w = 1400, h = STRIP_HEIGHT, minW = 420, minH = 96,
    dock = false,
  }, frame)
  if open then r.defer(loop) end
end
loop()
