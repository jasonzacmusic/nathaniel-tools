-- @description Click Levels
-- @version 1.0.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about
--   The two click levels and the accent pattern, in the docker.
--
--   BEAT 1 and OTHER BEATS are long faders: grab the handle and it moves from
--   where you took hold, click anywhere else and it goes there, Shift for fine,
--   the wheel for half-dB nudges, double-click to reset.
--
--   ACCENTS is a row of beats, one per beat of the bar. Click a beat to accent
--   it. Type a grouping like 3-3-3-3-4 and it lays the accents out for you.
--   REAPER does not let a script write its click pattern, so COPY puts it on
--   the clipboard and SETTINGS opens the one box it goes in - once.
--
--   The Korg's Fader 1 and Knob 1 drive the two faders here.
--
--   Requires the "Shared Libraries" package from this same repository.
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
local okClick, click = pcall(require, "nt_click")
if not (okSafe and okUi and okClick) then
  r.ShowMessageBox("Click Levels needs the 'Shared Libraries' package.\n\nExtensions > ReaPack > Browse packages > Nathaniel Tools > Shared Libraries > Install (or Install All).", "Click Levels", 0)
  return
end
do local ok, compat = pcall(require, "nt_imgui"); if ok then compat.install() end end
if not safe.require("Click Levels", { imgui = true }) then return end
if type(r.SNM_GetDoubleConfigVar) ~= "function" then
  r.ShowMessageBox("Click Levels needs the SWS extension.", "Click Levels", 0)
  return
end

local APP = "Click Levels"
local T = ui.tokens
local ACCENT = ui.accents.amber
local ctx = r.ImGui_CreateContext(APP)
ui.fonts(ctx)

local grab = {}
local beats = nil          -- accent pattern, one entry per beat
local beatsForMeter = nil  -- the meter those beats were built for
local groupText = "3+3+2"

--------------------------------------------------------------------------------
-- the fader
--------------------------------------------------------------------------------
local function dragBar(id, label, db, width, height)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_InvisibleButton(ctx, id, width, height)

  local hovered = r.ImGui_IsItemHovered(ctx)
  local active  = r.ImGui_IsItemActive(ctx)
  local newDb = db

  local fine = false
  if r.ImGui_GetKeyMods and r.ImGui_Mod_Shift then
    fine = (r.ImGui_GetKeyMods(ctx) & r.ImGui_Mod_Shift()) ~= 0
  end
  if hovered and r.ImGui_SetMouseCursor and r.ImGui_MouseCursor_ResizeEW then
    r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_ResizeEW())
  end

  local handleX = x + width * click.dbToPosition(db)

  if active then
    local mx = r.ImGui_GetMousePos(ctx)
    local state = grab[id]
    if not state then
      -- Taking hold of the handle moves it from where you grabbed, so the
      -- level never jumps out from under the pointer.
      state = { startX = mx, startDb = db }
      if math.abs(mx - handleX) > 16 then
        state.startDb = click.positionToDb((mx - x) / math.max(1, width))
      end
      grab[id] = state
    end
    local dx = (mx - state.startX) * (fine and 0.25 or 1.0)
    newDb = click.positionToDb(click.dbToPosition(state.startDb) + dx / math.max(1, width))
  else
    grab[id] = nil
    if hovered and r.ImGui_GetMouseWheel then
      local a, b = r.ImGui_GetMouseWheel(ctx)
      local wheel = (b ~= nil and b ~= 0) and b or (a or 0)
      if wheel ~= 0 then newDb = click.clampDb(db + (wheel > 0 and 1 or -1) * (fine and 0.1 or 0.5)) end
    end
  end
  if hovered and r.ImGui_IsMouseDoubleClicked(ctx, 0) then newDb = nil end

  local shown = newDb or db
  local fill = click.dbToPosition(shown)

  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + width, y + height, T.panel, 6)
  local colour = active and ui.shade(ACCENT, 0.18) or (hovered and ui.shade(ACCENT, 0.08) or ACCENT)
  if fill > 0 then r.ImGui_DrawList_AddRectFilled(dl, x, y, x + width * fill, y + height, colour, 6) end

  local zero = click.dbToPosition(0)
  r.ImGui_DrawList_AddRectFilled(dl, x + width * zero - 1, y + 3, x + width * zero + 1, y + height - 3, ui.alpha(T.white, 0.30))

  local hx = x + width * fill
  local hw = active and 9 or 7
  r.ImGui_DrawList_AddRectFilled(dl, hx - hw, y - 2, hx + hw, y + height + 2, T.white, 3)
  r.ImGui_DrawList_AddRectFilled(dl, hx - 1, y + 5, hx + 1, y + height - 5, ui.alpha(0x000000FF, 0.35), 1)
  r.ImGui_DrawList_AddRect(dl, x, y, x + width, y + height, hovered and ui.alpha(T.white, 0.35) or T.border, 6)

  ui.pushFont(ctx, "small", true)
  r.ImGui_DrawList_AddText(dl, x + 11, y + height / 2 - 7, ui.alpha(T.white, 0.95), label)
  local value = (shown <= click.MIN_DB) and "off" or string.format("%.1f dB", shown)
  local tw = r.ImGui_CalcTextSize(ctx, value)
  r.ImGui_DrawList_AddText(dl, x + width - tw - 11, y + height / 2 - 7, ui.alpha(T.white, 0.95), value)
  ui.popFont(ctx)

  return newDb, (newDb == nil)
end

--------------------------------------------------------------------------------
-- accents
--------------------------------------------------------------------------------
local lastWriteFailed = false

-- Take the pattern REAPER is actually using. Falls back to an accent on the
-- one, which is REAPER's own default.
local function refreshBeats(num)
  local live = click.readPattern()
  if live and #live == num then
    beats = live
  elseif not beats or beatsForMeter ~= num then
    beats = {}
    for i = 1, num do beats[i] = (i == 1) end
  end
  beatsForMeter = num
end

local function pushBeats()
  local ok = click.writePattern(beats)
  lastWriteFailed = not ok
end

--------------------------------------------------------------------------------
local function drawFrame()
  local avail = r.ImGui_GetContentRegionAvail(ctx) or 700
  local faderW = math.max(220, avail)

  local db1 = click.readDb("projmetrov1", click.DEFAULT_DB[1])
  local newDb1, reset1 = dragBar("##beat1", "BEAT 1", db1, faderW, 30)
  if reset1 then click.writeDb("projmetrov1", click.DEFAULT_DB[1])
  elseif newDb1 and math.abs(newDb1 - db1) > 0.01 then click.writeDb("projmetrov1", newDb1) end
  ui.tip(ctx, "The downbeat. Grab the handle, or click anywhere. Shift for fine, wheel to nudge, double-click to reset.")

  r.ImGui_Dummy(ctx, 1, 3)
  local db2 = click.readDb("projmetrov2", click.DEFAULT_DB[2])
  local newDb2, reset2 = dragBar("##beat2", "OTHER BEATS", db2, faderW, 30)
  if reset2 then click.writeDb("projmetrov2", click.DEFAULT_DB[2])
  elseif newDb2 and math.abs(newDb2 - db2) > 0.01 then click.writeDb("projmetrov2", newDb2) end
  ui.tip(ctx, "Every other beat. Same gestures.")

  -- ---- the accent row -----------------------------------------------------
  r.ImGui_Dummy(ctx, 1, 6)
  local num = click.meterAtCursor()
  refreshBeats(num)

  ui.dim(ctx, string.format("ACCENTS  %d beats", num))
  r.ImGui_SameLine(ctx)
  r.ImGui_Dummy(ctx, 8, 1)
  r.ImGui_SameLine(ctx)
  r.ImGui_SetNextItemWidth(ctx, 92)
  local changed, typed = r.ImGui_InputText(ctx, "##groups", groupText)
  if changed then groupText = typed end
  ui.tip(ctx, "Type how you feel the bar - 3-3-3-3-4, 7+6, 3+3+2 - and the beats below light up to match.")
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "LAY OUT", { w = 68, h = 20, small = true,
    tip = "Set the beats below from what you typed." }) then
    local groups = click.parseGroups(groupText)
    if groups then
      local laid = click.patternFromGroups(groups)
      beats = {}
      for i = 1, num do beats[i] = laid[i] or false end
      beatsForMeter = num
      pushBeats()
    end
  end

  r.ImGui_Dummy(ctx, 1, 3)
  -- One button per beat: the accented ones are lit. Click to change your mind.
  for i = 1, num do
    if i > 1 then r.ImGui_SameLine(ctx) end
    local on = beats[i]
    if ui.button(ctx, tostring(i), {
      kind = on and "primary" or "secondary", colour = ACCENT, w = 26, h = 22, small = true,
      tip = on and ("Beat " .. i .. " is accented. Click to make it ordinary.")
                or ("Beat " .. i .. " is ordinary. Click to accent it.")
    }) then beats[i] = not on; pushBeats() end
  end

  local text = click.patternString(beats)
  local groups = click.groupsFromPattern(beats)

  r.ImGui_Dummy(ctx, 1, 3)
  if lastWriteFailed then
    r.ImGui_TextColored(ctx, T.danger, "REAPER would not take that pattern")
  else
    ui.dim(ctx, text .. "   felt as " .. table.concat(groups, "+"))
  end
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "ALL OFF", { w = 66, h = 20, small = true,
    tip = "No accents at all - every beat the same." }) then
    for i = 1, #beats do beats[i] = false end
    pushBeats()
  end
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "ON THE 1", { w = 76, h = 20, small = true,
    tip = "Back to REAPER's default: the downbeat only." }) then
    for i = 1, #beats do beats[i] = (i == 1) end
    pushBeats()
  end
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "SETTINGS", { w = 74, h = 20, small = true,
    tip = "REAPER's own click settings: sounds and volumes." }) then
    click.fire(click.SETTINGS)
  end
end

--------------------------------------------------------------------------------
local reported = false
local function frame()
  local ok, err = pcall(drawFrame)
  if not ok then
    if not reported then
      reported = true
      local fh = io.open(r.GetResourcePath() .. "/nt_click_strip_error.log", "a")
      if fh then fh:write(os.date("%Y-%m-%d %H:%M:%S ") .. "Click Levels: " .. tostring(err) .. "\n"); fh:close() end
    end
    r.ImGui_TextColored(ctx, T.danger, "Click Levels: " .. tostring(err))
  end
end

local function loop()
  local open = ui.window(ctx, {
    title = APP, accent = ACCENT,
    w = 760, h = 220, minW = 320, minH = 140,
  }, frame)
  if open then r.defer(loop) end
end
loop()
