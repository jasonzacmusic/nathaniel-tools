-- @description Click Bar
-- @version 1.0.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about
--   One row, up in the toolbars: time signatures, pre-roll, and splitting a
--   long bar in two.
--
--   Hit a time signature anywhere in a bar and it lands on that bar's line -
--   you never have to park the cursor exactly. SPLIT breaks the bar you are in
--   into two: 15/8 becomes 7/8 + 8/8, 31/8 becomes 15/8 + 16/8, and the arrows
--   move where the split falls.
--
--   The beat levels and the accent pattern live in the Click Levels window,
--   down in the docker.
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
local okClick, click = pcall(require, "nt_click")
if not (okSafe and okUi and okClick) then
  r.ShowMessageBox("Click Bar needs the 'Shared Libraries' package.\n\nExtensions > ReaPack > Browse packages > Nathaniel Tools > Shared Libraries > Install (or Install All).", "Click Bar", 0)
  return
end
do local ok, compat = pcall(require, "nt_imgui"); if ok then compat.install() end end
if not safe.require("Click Bar", { imgui = true }) then return end
if type(r.SNM_GetDoubleConfigVar) ~= "function" then
  r.ShowMessageBox("Click Bar needs the SWS extension.", "Click Bar", 0)
  return
end

local APP = "Click Bar"
local T = ui.tokens
local ACCENT = ui.accents.amber
local ctx = r.ImGui_CreateContext(APP)
ui.fonts(ctx)

-- The meters worth a button. Anything else is typed into the odd box in the
-- Click Levels window.
local METERS = {
  { 4, 4 }, { 3, 4 }, { 2, 4 }, { 6, 8 }, { 5, 8 }, { 7, 8 }, { 8, 8 }, { 9, 8 }, { 12, 8 },
}

local prerollText = nil
local splitOffset = 0     -- nudges where a split falls

--------------------------------------------------------------------------------
local function drawFrame()
  local avail = r.ImGui_GetContentRegionAvail(ctx) or 800
  local h = 22

  -- ---- time signatures ----------------------------------------------------
  local num, den = click.meterAtCursor()
  for index, meter in ipairs(METERS) do
    if index > 1 then r.ImGui_SameLine(ctx) end
    local label = string.format("%d/%d", meter[1], meter[2])
    local current = (meter[1] == num and meter[2] == den)
    if ui.button(ctx, label, {
      kind = current and "primary" or "secondary", colour = ACCENT, w = 40, h = h, small = true,
      tip = "Set the bar the cursor is in to " .. label .. ". It snaps to the bar line."
    }) then click.setMeter(meter[1], meter[2]) end
  end

  -- ---- split --------------------------------------------------------------
  -- Half and half by default, and the arrows walk the split point.
  local half = math.floor(num / 2) + splitOffset
  half = math.max(1, math.min(num - 1, half))
  local other = num - half

  r.ImGui_SameLine(ctx)
  r.ImGui_Dummy(ctx, 10, 1)
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, "<", { w = 20, h = h, small = true, disabled = half <= 1,
    tip = "Move the split one beat earlier." }) then splitOffset = splitOffset - 1 end
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, string.format("SPLIT %d/%d + %d/%d", half, den, other, den), {
    kind = "primary", colour = ACCENT, w = 132, h = h, small = true,
    disabled = num < 2,
    tip = "Break this bar into two bars. The bar after them keeps the meter it had."
  }) then
    click.splitMeter(half, other, den)
    splitOffset = 0
  end
  r.ImGui_SameLine(ctx)
  if ui.button(ctx, ">", { w = 20, h = h, small = true, disabled = other <= 1,
    tip = "Move the split one beat later." }) then splitOffset = splitOffset + 1 end

  -- ---- pre-roll -----------------------------------------------------------
  r.ImGui_SameLine(ctx)
  r.ImGui_Dummy(ctx, 12, 1)
  r.ImGui_SameLine(ctx)
  local preroll = click.isOn(click.PREROLL)
  if ui.button(ctx, "PRE-ROLL", {
    kind = preroll and "primary" or "secondary", colour = ACCENT, w = 74, h = h, small = true,
    tip = "Count in before recording actually starts."
  }) then click.fire(click.PREROLL) end

  r.ImGui_SameLine(ctx)
  if prerollText == nil then prerollText = click.formatBars(click.prerollBars()) end
  r.ImGui_SetNextItemWidth(ctx, 52)
  local changed, typed = r.ImGui_InputText(ctx, "##preroll", prerollText)
  if changed then
    prerollText = typed
    local value = tonumber(typed)
    if value then click.setPrerollBars(value) end
  end
  ui.tip(ctx, "How many bars of pre-roll. Fractions are allowed: 0.5 for half a bar, 0.25 for a beat of four.")
  r.ImGui_SameLine(ctx)
  ui.dim(ctx, "bars")

  if avail > 720 then
    r.ImGui_SameLine(ctx)
    r.ImGui_Dummy(ctx, 8, 1)
    r.ImGui_SameLine(ctx)
    ui.dim(ctx, string.format("bar is %d/%d", num, den))
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
      if fh then fh:write(os.date("%Y-%m-%d %H:%M:%S ") .. "Click Bar: " .. tostring(err) .. "\n"); fh:close() end
    end
    r.ImGui_TextColored(ctx, T.danger, "Click Bar: " .. tostring(err))
  end
end

-- Sits in the toolbar row, top right.
local TOP_RIGHT_DOCKER = -6
local dockFrames = (r.GetExtState("NT_UI", "dock:Click Bar") ~= "0") and 3 or 0

local function loop()
  if dockFrames > 0 then
    dockFrames = dockFrames - 1
    if r.ImGui_SetNextWindowDockID then
      r.ImGui_SetNextWindowDockID(ctx, TOP_RIGHT_DOCKER, r.ImGui_Cond_Always and r.ImGui_Cond_Always() or 1)
    end
  end
  local open = ui.window(ctx, {
    title = APP, accent = ACCENT,
    w = 820, h = 52, minW = 320, minH = 34,
  }, frame)
  if open then r.defer(loop) end
end
loop()
