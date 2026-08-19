-- @noindex
-- Shared library for the Nathaniel Tools. Not a standalone action.
-- Distributed by the "Shared Libraries" package via its @provides tag.

--[[
  nt_ui.lua  -  the one look every Nathaniel Tools window shares
  ----------------------------------------------------------------------------
  WHY THIS FILE EXISTS

  Six windows were each hand-styling ReaImGui: five different "muted grey"
  hexes, four different log panels, buttons of every size, and no two headers
  alike.  Track Settings Transfer had no theme at all.  StageRig created fonts
  with an API that ReaImGui 0.10 had already changed, and died on open.

  This file owns all of that in one place:

    * tokens      - one dark palette, one accent per app (its identity colour)
    * fonts       - system UI font at four sizes; works on ReaImGui 0.9 and 0.10
    * window()    - theme push, Begin/End, dock handling, first size, and an
                    error net that keeps the window alive and SHOWS the error
    * header()    - app name, one-line purpose, right-aligned controls
    * button()    - primary / secondary / danger / ghost, one hit size
    * segmented() - "pick one of these" (print mode, scope, palette)
    * table()     - the standard list: frozen header, row stripes, no wall of
                    borders, sized to leave room for the footer
    * status()    - one always-visible line saying what just happened, with a
                    log you can open.  No more actions that appear to do nothing.
    * confirm()   - a modal for anything destructive.  Nothing rewrites your
                    session on a single click any more.
    * empty()     - what to do when there is nothing to show
    * swatch(), pill(), hint(), section(), tip(), combo(), tick()

  COLOUR LANGUAGE (locked in docs/TECH_BRIEF.md)
    green   structure    Folders & Flow, Track Settings Transfer
    amber   delivery     Stem Print & Handoff, MIDI Batch Export
    violet  performance  StageRig
    teal    look         Palette & Look

  Colours are 0xRRGGBBAA, as ReaImGui wants them.

  Author: Jason Zac / Nathaniel School of Music
--]]

local r = reaper
local M = {}

--------------------------------------------------------------------------------
-- small helpers
--------------------------------------------------------------------------------

-- Enum accessor that tolerates a missing constant (renamed between ReaImGui
-- releases). Returns nil instead of throwing, so a theme push can skip it and
-- count only what it really pushed.
local function E(name)
  local f = r["ImGui_" .. name]
  if type(f) == "function" then
    local ok, v = pcall(f)
    if ok then return v end
  end
  return nil
end
M.E = E

local function clamp(x, lo, hi) if x < lo then return lo elseif x > hi then return hi else return x end end

-- 0xRRGGBBAA <-> components
local function rgba(c)
  return (c >> 24) & 0xFF, (c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF
end
local function pack(rr, gg, bb, aa)
  return (clamp(math.floor(rr + 0.5), 0, 255) << 24)
       | (clamp(math.floor(gg + 0.5), 0, 255) << 16)
       | (clamp(math.floor(bb + 0.5), 0, 255) << 8)
       | clamp(math.floor((aa or 255) + 0.5), 0, 255)
end
M.rgba, M.pack = rgba, pack

-- Mix colour c towards white (f>0) or black (f<0), keeping alpha.
function M.shade(c, f)
  local rr, gg, bb, aa = rgba(c)
  if f >= 0 then
    return pack(rr + (255 - rr) * f, gg + (255 - gg) * f, bb + (255 - bb) * f, aa)
  else
    f = -f
    return pack(rr * (1 - f), gg * (1 - f), bb * (1 - f), aa)
  end
end
function M.alpha(c, a) return (c & ~0xFF) | clamp(math.floor(a * 255 + 0.5), 0, 255) end
-- REAPER native colour (from GetTrackColor etc.) -> ImGui colour
function M.fromNative(native)
  if not native or native == 0 then return nil end
  local rr, gg, bb = r.ColorFromNative(native)
  return pack(rr, gg, bb, 255)
end
-- Pick black or white text for a background colour.
function M.textOn(c)
  local rr, gg, bb = rgba(c)
  local lum = (0.299 * rr + 0.587 * gg + 0.114 * bb) / 255
  return lum > 0.6 and 0x101217FF or 0xF4F5F8FF
end

--------------------------------------------------------------------------------
-- tokens
--------------------------------------------------------------------------------
M.tokens = {
  bg      = 0x101217FF,  -- window
  panel   = 0x171A21FF,  -- inputs, table header, child panels
  raised  = 0x1F2330FF,  -- secondary buttons, hovered rows
  border  = 0x2A2F3BFF,
  text    = 0xE9EBF1FF,
  muted   = 0x8C93A4FF,
  dim     = 0x5B6170FF,
  ok      = 0x4CC38AFF,
  warn    = 0xE8B23AFF,
  danger  = 0xE0455AFF,
  info    = 0x4F8EF7FF,
  white   = 0xFFFFFFFF,
}

M.accents = {
  green  = 0x3FA95EFF,
  amber  = 0xE0912EFF,
  violet = 0x8A5CF0FF,
  teal   = 0x2FB7A6FF,
}

--------------------------------------------------------------------------------
-- fonts  (ReaImGui 0.9 and 0.10 have different font APIs)
--------------------------------------------------------------------------------
-- 0.10: CreateFont(family, flags); PushFont(ctx, font, size)   one font, any size
-- 0.9 : CreateFont(family, size, flags); PushFont(ctx, font)   one font per size
local SIZES = { small = 12, body = 14, title = 19, big = 34, huge = 46 }
M.sizes = SIZES

local function reaimguiMinor()
  if not r.ImGui_GetVersion then return 0 end
  local ok, a, b, c = pcall(r.ImGui_GetVersion)
  local v = ok and (type(c) == "string" and c or (type(a) == "string" and a)) or "0"
  local maj, min = tostring(v):match("^(%d+)%.(%d+)")
  maj, min = tonumber(maj) or 0, tonumber(min) or 0
  return maj * 100 + min   -- 0.10 -> 10, 1.0 -> 100
end

local FONT_API_NEW = nil     -- lazily decided
local function fontApiIsNew()
  if FONT_API_NEW == nil then FONT_API_NEW = reaimguiMinor() >= 10 end
  return FONT_API_NEW
end

local state = {}   -- per-context state, keyed by ctx

local function S(ctx)
  local s = state[ctx]
  if not s then s = { fonts = {}, popups = {}, log = {}, status = nil, statusLevel = "info", statusT = 0 }; state[ctx] = s end
  return s
end

-- Creates and attaches the fonts for a context. Safe to call every frame; it
-- only does the work once. Returns false if fonts could not be made (ReaImGui
-- too old) - the apps then run on ImGui's default font, which is fine.
function M.fonts(ctx)
  local s = S(ctx)
  if s.fontsReady ~= nil then return s.fontsReady end
  s.fontsReady = false
  if not (r.ImGui_CreateFont and r.ImGui_Attach) then return false end
  local bold = E("FontFlags_Bold") or 0
  local ok = pcall(function()
    if fontApiIsNew() then
      s.fonts.regular = r.ImGui_CreateFont("sans-serif", 0)
      s.fonts.bold    = r.ImGui_CreateFont("sans-serif", bold)
      r.ImGui_Attach(ctx, s.fonts.regular)
      r.ImGui_Attach(ctx, s.fonts.bold)
    else
      for name, px in pairs(SIZES) do
        s.fonts[name] = r.ImGui_CreateFont("sans-serif", px, 0)
        r.ImGui_Attach(ctx, s.fonts[name])
        s.fonts[name .. "_bold"] = r.ImGui_CreateFont("sans-serif", px, bold)
        r.ImGui_Attach(ctx, s.fonts[name .. "_bold"])
      end
    end
  end)
  s.fontsReady = ok
  return ok
end

-- role: "small" | "body" | "title" | "big" | "huge"; bold: boolean.
-- Does nothing (but stays balanced) when fonts are unavailable.
function M.pushFont(ctx, role, bold)
  local s = S(ctx)
  role = role or "body"
  if not s.fontsReady then s._nofontPush = (s._nofontPush or 0) + 1; return end
  if fontApiIsNew() then
    r.ImGui_PushFont(ctx, bold and s.fonts.bold or s.fonts.regular, SIZES[role] or SIZES.body)
  else
    local f = s.fonts[(role) .. (bold and "_bold" or "")] or s.fonts.body
    r.ImGui_PushFont(ctx, f)
  end
end
function M.popFont(ctx)
  local s = S(ctx)
  if not s.fontsReady then s._nofontPush = (s._nofontPush or 1) - 1; return end
  r.ImGui_PopFont(ctx)
end

--------------------------------------------------------------------------------
-- theme
--------------------------------------------------------------------------------
-- Pushes the whole look for one frame. Returns a closure that pops exactly
-- what was pushed, so counts can never drift.
function M.pushTheme(ctx, accent)
  local T = M.tokens
  local A = accent or M.accents.teal
  local nCol, nVar = 0, 0
  local function col(name, c)
    local e = E("Col_" .. name)
    if e then r.ImGui_PushStyleColor(ctx, e, c); nCol = nCol + 1 end
  end
  local function var(name, a, b)
    local e = E("StyleVar_" .. name)
    if e then
      if b ~= nil then r.ImGui_PushStyleVar(ctx, e, a, b) else r.ImGui_PushStyleVar(ctx, e, a) end
      nVar = nVar + 1
    end
  end

  var("WindowRounding", 8)
  var("ChildRounding", 6)
  var("FrameRounding", 6)
  var("PopupRounding", 8)
  var("GrabRounding", 6)
  var("TabRounding", 6)
  var("ScrollbarRounding", 8)
  var("ScrollbarSize", 11)
  var("WindowPadding", 16, 12)
  var("FramePadding", 9, 5)
  var("ItemSpacing", 8, 6)
  var("ItemInnerSpacing", 6, 4)
  var("CellPadding", 8, 3)
  var("WindowBorderSize", 0)
  var("ChildBorderSize", 1)
  var("FrameBorderSize", 0)
  var("PopupBorderSize", 1)
  var("IndentSpacing", 18)
  var("SeparatorTextBorderSize", 1)
  var("SeparatorTextPadding", 0, 6)

  col("WindowBg", T.bg)
  col("ChildBg", 0x00000000)
  col("PopupBg", T.panel)
  col("Border", T.border)
  col("BorderShadow", 0x00000000)
  col("Text", T.text)
  col("TextDisabled", T.dim)
  col("FrameBg", T.raised)                     -- inputs + checkboxes; must stay visible on striped table rows
  col("FrameBgHovered", M.shade(T.raised, 0.08))
  col("FrameBgActive", M.shade(T.raised, 0.14))
  col("TitleBg", T.bg)
  col("TitleBgActive", T.bg)
  col("TitleBgCollapsed", T.bg)
  col("MenuBarBg", T.panel)
  col("ScrollbarBg", 0x00000000)
  col("ScrollbarGrab", T.raised)
  col("ScrollbarGrabHovered", M.shade(T.raised, 0.15))
  col("ScrollbarGrabActive", M.shade(T.raised, 0.25))
  col("CheckMark", A)
  col("SliderGrab", A)
  col("SliderGrabActive", M.shade(A, 0.15))
  col("Button", T.raised)                     -- default = secondary
  col("ButtonHovered", M.shade(T.raised, 0.10))
  col("ButtonActive", M.shade(T.raised, -0.15))
  col("Header", M.alpha(A, 0.35))
  col("HeaderHovered", M.alpha(A, 0.50))
  col("HeaderActive", M.alpha(A, 0.65))
  col("Separator", T.border)
  col("SeparatorHovered", A)
  col("SeparatorActive", A)
  col("ResizeGrip", 0x00000000)
  col("ResizeGripHovered", M.alpha(A, 0.4))
  col("ResizeGripActive", M.alpha(A, 0.7))
  col("Tab", T.panel)
  col("TabHovered", M.alpha(A, 0.55))
  col("TabSelected", M.alpha(A, 0.85))
  col("TabActive", M.alpha(A, 0.85))         -- old name, harmless if absent
  col("TabDimmed", T.panel)
  col("TabDimmedSelected", M.alpha(A, 0.55))
  col("TabUnfocused", T.panel)
  col("TabUnfocusedActive", M.alpha(A, 0.55))
  col("TableHeaderBg", T.panel)
  col("TableBorderStrong", T.border)
  col("TableBorderLight", M.alpha(T.border, 0.55))
  col("TableRowBg", 0x00000000)
  col("TableRowBgAlt", 0xFFFFFF07)
  col("TextSelectedBg", M.alpha(A, 0.35))
  col("NavCursor", A)
  col("NavHighlight", A)
  col("ModalWindowDimBg", 0x0A0B10A0)
  col("PlotHistogram", A)
  col("DockingPreview", M.alpha(A, 0.5))

  local s = S(ctx)
  s.accent = A
  return function()
    r.ImGui_PopStyleColor(ctx, nCol)
    r.ImGui_PopStyleVar(ctx, nVar)
  end
end

--------------------------------------------------------------------------------
-- window  (theme, Begin/End, first size, docking, error net)
--------------------------------------------------------------------------------
-- spec = { title=, accent=, w=, h=, minW=, minH=, dock=(-1|0|nil), flags= }
-- frameFn() draws the body. Returns `open` (false when the user closed it).
--
-- On a Lua error inside frameFn the window STAYS UP and shows the error in
-- the status line - the old apps died with a REAPER error box.
function M.window(ctx, spec, frameFn)
  local s = S(ctx)
  M.fonts(ctx)
  if s.dockPending ~= nil then r.ImGui_SetNextWindowDockID(ctx, s.dockPending); s.dockPending = nil end
  -- Dock by default. The user's last choice (the Dock toggle) is remembered per
  -- window in ExtState, so an app opens where it was left: in the docker unless
  -- you floated it. Jason: "set up to load in the docker at the word go".
  if not s.sized then
    s.dockKey = "dock:" .. tostring(spec.title or "window")
    local pref = r.GetExtState("NT_UI", s.dockKey)
    local wantDock = (pref == "" and (spec.dock ~= false)) or pref == "1"
    r.ImGui_SetNextWindowDockID(ctx, wantDock and -1 or 0, E("Cond_Always") or 0)
  end
  if not s.sized then
    r.ImGui_SetNextWindowSize(ctx, spec.w or 820, spec.h or 620, E("Cond_FirstUseEver") or 0)
    -- a window closed while collapsed would reopen as a bare title bar and
    -- look broken; always open expanded
    if r.ImGui_SetNextWindowCollapsed then r.ImGui_SetNextWindowCollapsed(ctx, false, E("Cond_Always") or 0) end
    s.sized = true
  end
  if r.ImGui_SetNextWindowSizeConstraints and (spec.minW or spec.minH) then
    r.ImGui_SetNextWindowSizeConstraints(ctx, spec.minW or 320, spec.minH or 200, 1e9, 1e9)
  end
  -- heartbeat so "Open Dock" knows this window is alive (and does not relaunch it)
  local now = os.time()
  if s.lastBeat ~= now then s.lastBeat = now; r.SetExtState("NT_UI", "alive:" .. tostring(spec.title or "window"), tostring(now), false) end
  local pop = M.pushTheme(ctx, spec.accent)
  M.pushFont(ctx, "body")
  local flags = spec.flags or 0
  local vis, open = r.ImGui_Begin(ctx, spec.title, true, flags)
  if vis then
    local ok, err = pcall(frameFn)
    if not ok then
      s.lastError = tostring(err)
      M.say(ctx, "Something went wrong (window kept open): " .. tostring(err), "danger")
    end
    -- End is wrapped too: an unbalanced push inside a failed frame would
    -- otherwise raise here and kill the script.
    pcall(r.ImGui_End, ctx)
  end
  M.popFont(ctx)
  pop()
  return open
end

function M.requestDock(ctx, docked)
  local s = S(ctx)
  s.dockPending = docked and -1 or 0
  if s.dockKey then r.SetExtState("NT_UI", s.dockKey, docked and "1" or "0", true) end
end

--------------------------------------------------------------------------------
-- text helpers
--------------------------------------------------------------------------------
function M.text(ctx, str, colour)
  if colour then r.ImGui_TextColored(ctx, colour, str) else r.ImGui_Text(ctx, str) end
end
function M.hint(ctx, str) r.ImGui_TextColored(ctx, M.tokens.muted, str) end
function M.dim(ctx, str) r.ImGui_TextColored(ctx, M.tokens.dim, str) end
function M.tip(ctx, str)
  if str and str ~= "" and r.ImGui_IsItemHovered(ctx, E("HoveredFlags_ForTooltip") or 0) then
    r.ImGui_BeginTooltip(ctx)
    r.ImGui_PushTextWrapPos(ctx, 320)
    r.ImGui_Text(ctx, str)
    r.ImGui_PopTextWrapPos(ctx)
    r.ImGui_EndTooltip(ctx)
  end
end
function M.wrapped(ctx, str, colour)
  if colour then r.ImGui_PushStyleColor(ctx, E("Col_Text"), colour) end
  r.ImGui_TextWrapped(ctx, str)
  if colour then r.ImGui_PopStyleColor(ctx) end
end

-- Small-caps-feel section label with a rule after it.
function M.section(ctx, label)
  r.ImGui_Dummy(ctx, 0, 2)
  M.pushFont(ctx, "small", true)
  r.ImGui_TextColored(ctx, M.tokens.muted, string.upper(label))
  M.popFont(ctx)
  local x1, y1 = r.ImGui_GetCursorScreenPos(ctx)
  local w = r.ImGui_GetContentRegionAvail(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  r.ImGui_DrawList_AddLine(dl, x1, y1 + 1, x1 + w, y1 + 1, M.tokens.border, 1)
  r.ImGui_Dummy(ctx, 0, 3)
end

-- Header band: coloured title, muted tagline, and a right-aligned control
-- group drawn by rightFn(). Draw once at the top of every app.
function M.header(ctx, title, tagline, rightFn, rightWidth)
  local s = S(ctx)
  local A = s.accent or M.accents.teal
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local w = r.ImGui_GetContentRegionAvail(ctx)
  -- accent bar on the left
  r.ImGui_DrawList_AddRectFilled(dl, x, y + 2, x + 4, y + 26, A, 2)
  r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + 12)
  M.pushFont(ctx, "title", true)
  r.ImGui_TextColored(ctx, A, title)
  M.popFont(ctx)
  if tagline and tagline ~= "" then
    r.ImGui_SameLine(ctx, 0, 12)
    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_TextColored(ctx, M.tokens.muted, tagline)
  end
  if rightFn then
    local rw = rightWidth or 160
    r.ImGui_SameLine(ctx)
    M.rightAlign(ctx, rw)
    rightFn()
  end
  r.ImGui_Dummy(ctx, 0, 2)
  local x2, y2 = r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_DrawList_AddLine(dl, x2, y2, x2 + w, y2, M.tokens.border, 1)
  r.ImGui_Dummy(ctx, 0, 6)
end

-- Standard "Dock" toggle for a header's right side.
function M.dockToggle(ctx)
  local docked = r.ImGui_IsWindowDocked(ctx)
  local ch, v = r.ImGui_Checkbox(ctx, "Dock", docked)
  if ch then M.requestDock(ctx, v) end
  M.tip(ctx, "Put this window in REAPER's docker so it lives with the mixer, or float it.")
end

--------------------------------------------------------------------------------
-- buttons
--------------------------------------------------------------------------------
-- kind: "primary" (accent fill) | "secondary" (default) | "danger" | "ghost"
-- opts: { w=, h=, tip=, disabled=, colour= (override accent), small= }
function M.button(ctx, label, opts)
  opts = opts or {}
  local T = M.tokens
  local s = S(ctx)
  local kind = opts.kind or "secondary"
  local base
  if kind == "primary" then base = opts.colour or s.accent or M.accents.teal
  elseif kind == "danger" then base = T.danger
  elseif kind == "ghost" then base = 0x00000000
  else base = T.raised end
  local n = 0
  local function col(name, c) local e = E("Col_" .. name); if e then r.ImGui_PushStyleColor(ctx, e, c); n = n + 1 end end
  if kind == "primary" or kind == "danger" then
    col("Button", base); col("ButtonHovered", M.shade(base, 0.12)); col("ButtonActive", M.shade(base, -0.18))
    col("Text", M.textOn(base))
  elseif kind == "ghost" then
    col("Button", 0x00000000); col("ButtonHovered", M.alpha(T.raised, 0.7)); col("ButtonActive", T.raised)
    col("Text", T.muted)
  end
  local nv = 0
  if opts.small then
    local e = E("StyleVar_FramePadding"); if e then r.ImGui_PushStyleVar(ctx, e, 7, 3); nv = nv + 1 end
  end
  if opts.disabled then r.ImGui_BeginDisabled(ctx, true) end
  local clicked = r.ImGui_Button(ctx, label, opts.w or 0, opts.h or 0)
  if opts.disabled then r.ImGui_EndDisabled(ctx) end
  if nv > 0 then r.ImGui_PopStyleVar(ctx, nv) end
  if n > 0 then r.ImGui_PopStyleColor(ctx, n) end
  M.tip(ctx, opts.tip)
  return clicked and not opts.disabled
end

-- A row of mutually exclusive choices. items = { {id=, label=, tip=}, ... }
-- Returns the (possibly new) current id.
function M.segmented(ctx, id, items, current, opts)
  opts = opts or {}
  local T = M.tokens
  local s = S(ctx)
  local A = s.accent or M.accents.teal
  r.ImGui_PushID(ctx, id)
  local n = 0
  local e = E("StyleVar_ItemSpacing"); if e then r.ImGui_PushStyleVar(ctx, e, 2, 7); n = n + 1 end
  for i, it in ipairs(items) do
    local on = it.id == current
    local nc = 0
    local function col(name, c) local ee = E("Col_" .. name); if ee then r.ImGui_PushStyleColor(ctx, ee, c); nc = nc + 1 end end
    if on then
      col("Button", A); col("ButtonHovered", M.shade(A, 0.1)); col("ButtonActive", M.shade(A, -0.15)); col("Text", M.textOn(A))
    else
      col("Button", T.panel); col("ButtonHovered", T.raised); col("ButtonActive", M.shade(T.raised, -0.1)); col("Text", T.muted)
    end
    if r.ImGui_Button(ctx, it.label, opts.w or 0, opts.h or 0) then current = it.id end
    r.ImGui_PopStyleColor(ctx, nc)
    M.tip(ctx, it.tip)
    if i < #items then r.ImGui_SameLine(ctx) end
  end
  if n > 0 then r.ImGui_PopStyleVar(ctx, n) end
  r.ImGui_PopID(ctx)
  return current
end

-- Checkbox with a tooltip. Returns changed, value.
function M.toggle(ctx, label, value, tipText)
  local ch, v = r.ImGui_Checkbox(ctx, label, value)
  M.tip(ctx, tipText)
  return ch, v
end

-- Combo over a plain list of strings. Returns changed, newIndex (1-based).
function M.combo(ctx, id, items, idx, opts)
  opts = opts or {}
  if opts.w then r.ImGui_SetNextItemWidth(ctx, opts.w) end
  local changed = false
  local preview = items[idx] or (opts.placeholder or "-")
  if r.ImGui_BeginCombo(ctx, id, preview) then
    for i, it in ipairs(items) do
      if r.ImGui_Selectable(ctx, it, i == idx) then idx = i; changed = true end
    end
    r.ImGui_EndCombo(ctx)
  end
  M.tip(ctx, opts.tip)
  return changed, idx
end

-- Little coloured tag: "BUS", "MIDI", "3 hits". Returns true if clicked.
function M.pill(ctx, label, colour)
  colour = colour or M.tokens.muted
  local n = 0
  local function col(name, c) local e = E("Col_" .. name); if e then r.ImGui_PushStyleColor(ctx, e, c); n = n + 1 end end
  col("Button", M.alpha(colour, 0.20)); col("ButtonHovered", M.alpha(colour, 0.28)); col("ButtonActive", M.alpha(colour, 0.36))
  col("Text", colour)
  local nv = 0
  local e = E("StyleVar_FramePadding"); if e then r.ImGui_PushStyleVar(ctx, e, 7, 2); nv = nv + 1 end
  local e2 = E("StyleVar_FrameRounding"); if e2 then r.ImGui_PushStyleVar(ctx, e2, 9); nv = nv + 1 end
  M.pushFont(ctx, "small", true)
  local clicked = r.ImGui_Button(ctx, label)
  M.popFont(ctx)
  if nv > 0 then r.ImGui_PopStyleVar(ctx, nv) end
  if n > 0 then r.ImGui_PopStyleColor(ctx, n) end
  return clicked
end

-- Colour swatch. Returns true when clicked. opts { w=, h=, tip= }
function M.swatch(ctx, id, colour, opts)
  opts = opts or {}
  local T = M.tokens
  local shown = colour or 0x00000000
  local flags = (E("ColorEditFlags_NoTooltip") or 0) | (E("ColorEditFlags_NoAlpha") or 0)
  if not colour then flags = flags | (E("ColorEditFlags_AlphaPreview") or 0) end
  local clicked = r.ImGui_ColorButton(ctx, id, colour and shown or T.panel, flags, opts.w or 22, opts.h or 18)
  M.tip(ctx, opts.tip)
  return clicked
end

--------------------------------------------------------------------------------
-- tables
--------------------------------------------------------------------------------
-- cols = { {name=, w=} , ... }  (w = fixed px, nil = stretch)
-- opts = { height=, reserve= (px to leave below), stripes=true, borders=true, id= }
-- Returns true when the table began (call ImGui_EndTable yourself).
function M.tableBegin(ctx, id, cols, opts)
  opts = opts or {}
  local flags = (E("TableFlags_RowBg") or 0) | (E("TableFlags_ScrollY") or 0)
             | (E("TableFlags_BordersInnerH") or 0) | (E("TableFlags_PadOuterX") or 0)
  if opts.borders then flags = flags | (E("TableFlags_BordersOuter") or 0) end
  if opts.resizable then flags = flags | (E("TableFlags_Resizable") or 0) end
  local h = opts.height
  if not h then
    local _, avail = r.ImGui_GetContentRegionAvail(ctx)
    -- when the status log is open the footer is taller; keep the table clear of it
    local extra = S(ctx).logOpen and ((opts.logHeight or 140) + 8) or 0
    h = math.max(opts.minHeight or 90, avail - (opts.reserve or 0) - extra)
  end
  if not r.ImGui_BeginTable(ctx, id, #cols, flags, 0, h) then return false end
  r.ImGui_TableSetupScrollFreeze(ctx, 0, 1)
  for _, c in ipairs(cols) do
    if c.w then r.ImGui_TableSetupColumn(ctx, c.name, E("TableColumnFlags_WidthFixed") or 0, c.w)
    else r.ImGui_TableSetupColumn(ctx, c.name, E("TableColumnFlags_WidthStretch") or 0) end
  end
  M.pushFont(ctx, "small", true)
  r.ImGui_TableHeadersRow(ctx)
  M.popFont(ctx)
  return true
end

-- Tick column with drag-paint: press on one box and drag down to paint many.
-- paint = a table you keep between frames ({}) ; returns changed, value.
function M.tick(ctx, id, value, paint)
  local ch, v = r.ImGui_Checkbox(ctx, id, value)
  if ch then paint.active = true; paint.value = v; return true, v end
  if paint.active then
    if not r.ImGui_IsMouseDown(ctx, 0) then paint.active = false
    elseif r.ImGui_IsItemHovered(ctx) and value ~= paint.value then return true, paint.value end
  end
  return false, value
end

--------------------------------------------------------------------------------
-- status line + log
--------------------------------------------------------------------------------
-- level: "info" | "ok" | "warn" | "danger"
function M.say(ctx, msg, level)
  local s = S(ctx)
  s.status, s.statusLevel, s.statusT = msg, level or "info", r.time_precise()
  s.log[#s.log + 1] = { t = os.date("%H:%M:%S"), msg = msg, level = level or "info" }
  if #s.log > 400 then table.remove(s.log, 1) end
end
function M.clearLog(ctx) S(ctx).log = {} end
function M.logLines(ctx) return S(ctx).log end

local LEVEL_COL = { info = "muted", ok = "ok", warn = "warn", danger = "danger" }

-- Draw the footer: a dot + last message, plus a "Log" toggle that opens the
-- history. Call it LAST in your frame; it uses whatever height is left.
-- opts = { logHeight= (default 110), always=false }
function M.status(ctx, opts)
  opts = opts or {}
  local s = S(ctx)
  local T = M.tokens
  r.ImGui_Spacing(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local w = r.ImGui_GetContentRegionAvail(ctx)
  r.ImGui_DrawList_AddLine(dl, x, y, x + w, y, T.border, 1)
  r.ImGui_Dummy(ctx, 0, 4)
  local lvl = s.statusLevel or "info"
  local c = T[LEVEL_COL[lvl] or "muted"]
  local cx, cy = r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_DrawList_AddCircleFilled(dl, cx + 6, cy + 10, 4, c)
  r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + 18)
  r.ImGui_AlignTextToFramePadding(ctx)
  local msg = s.status or (opts.idle or "Ready.")
  local avail = r.ImGui_GetContentRegionAvail(ctx)
  r.ImGui_PushTextWrapPos(ctx, r.ImGui_GetCursorPosX(ctx) + avail - 70)
  r.ImGui_TextColored(ctx, s.status and T.text or T.muted, msg)
  r.ImGui_PopTextWrapPos(ctx)
  r.ImGui_SameLine(ctx, math.max(0, r.ImGui_GetCursorPosX(ctx) + avail - 60))
  local n = #s.log
  local label = s.logOpen and "Hide log" or ("Log" .. (n > 0 and (" (" .. n .. ")") or ""))
  if M.button(ctx, label, { kind = "ghost", small = true, tip = "Everything this window has done this session." }) then
    s.logOpen = not s.logOpen
  end
  if s.logOpen then
    local flags = E("ChildFlags_Borders") or E("ChildFlags_Border") or 0
    local _, availH = r.ImGui_GetContentRegionAvail(ctx)
    local h = math.min(opts.logHeight or 140, math.max(60, availH))
    if r.ImGui_BeginChild(ctx, "##ntlog", 0, h, flags) then
      M.pushFont(ctx, "small")
      for i = #s.log, 1, -1 do
        local e = s.log[i]
        r.ImGui_TextColored(ctx, T.dim, e.t); r.ImGui_SameLine(ctx, 0, 8)
        r.ImGui_TextColored(ctx, T[LEVEL_COL[e.level] or "muted"] , e.msg)
      end
      M.popFont(ctx)
      r.ImGui_EndChild(ctx)
    end
  end
end

--------------------------------------------------------------------------------
-- empty state
--------------------------------------------------------------------------------
-- Draws a calm centred message with an optional action button.
-- opts = { button=, onClick=fn }
function M.empty(ctx, headline, hintText, opts)
  opts = opts or {}
  local T = M.tokens
  local w, h = r.ImGui_GetContentRegionAvail(ctx)
  r.ImGui_Dummy(ctx, 0, math.max(10, h * 0.25))
  M.pushFont(ctx, "title", true)
  local tw = r.ImGui_CalcTextSize(ctx, headline)
  r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + math.max(0, (w - tw) / 2))
  r.ImGui_TextColored(ctx, T.text, headline)
  M.popFont(ctx)
  if hintText then
    local maxw = math.min(460, w - 20)
    local hw = r.ImGui_CalcTextSize(ctx, hintText, false, maxw)
    hw = math.min(hw, maxw)
    local x0 = r.ImGui_GetCursorPosX(ctx) + math.max(0, (w - hw) / 2)
    r.ImGui_SetCursorPosX(ctx, x0)
    r.ImGui_PushTextWrapPos(ctx, x0 + maxw)
    r.ImGui_TextColored(ctx, T.muted, hintText)
    r.ImGui_PopTextWrapPos(ctx)
  end
  if opts.button then
    r.ImGui_Dummy(ctx, 0, 6)
    local bw = 180
    r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + math.max(0, (w - bw) / 2))
    if M.button(ctx, opts.button, { kind = "primary", w = bw }) and opts.onClick then opts.onClick() end
  end
end

--------------------------------------------------------------------------------
-- confirm  (modal for anything destructive)
--------------------------------------------------------------------------------
-- Usage:   if ui.button(ctx, "Clear all") then ui.ask(ctx, "clear") end
--          if ui.confirm(ctx, "clear", { title="Clear every rule?",
--               text="This cannot be undone.", ok="Clear", danger=true }) then ... end
function M.ask(ctx, id) S(ctx).popups[id] = true end

function M.confirm(ctx, id, opts)
  opts = opts or {}
  local s = S(ctx)
  local T = M.tokens
  local pid = "##confirm_" .. id
  if s.popups[id] then r.ImGui_OpenPopup(ctx, pid); s.popups[id] = nil end
  local result = false
  if r.ImGui_SetNextWindowSize then r.ImGui_SetNextWindowSize(ctx, 420, 0, E("Cond_Appearing") or 0) end
  local flags = (E("WindowFlags_NoResize") or 0) | (E("WindowFlags_NoTitleBar") or 0) | (E("WindowFlags_AlwaysAutoResize") or 0)
  local vis = r.ImGui_BeginPopupModal(ctx, pid, nil, flags)
  if vis then
    M.pushFont(ctx, "title", true)
    r.ImGui_TextColored(ctx, opts.danger and T.danger or T.text, opts.title or "Are you sure?")
    M.popFont(ctx)
    if opts.text then r.ImGui_PushTextWrapPos(ctx, 400); r.ImGui_TextColored(ctx, T.muted, opts.text); r.ImGui_PopTextWrapPos(ctx) end
    r.ImGui_Dummy(ctx, 0, 6)
    if M.button(ctx, opts.ok or "OK", { kind = opts.danger and "danger" or "primary", w = 140 }) then
      result = true; r.ImGui_CloseCurrentPopup(ctx)
    end
    r.ImGui_SameLine(ctx)
    if M.button(ctx, opts.cancel or "Cancel", { w = 100 }) then r.ImGui_CloseCurrentPopup(ctx) end
    local esc = E("Key_Escape")
    if esc and r.ImGui_IsKeyPressed(ctx, esc) then r.ImGui_CloseCurrentPopup(ctx) end
    r.ImGui_EndPopup(ctx)
  end
  return result
end

--------------------------------------------------------------------------------
-- layout helpers
--------------------------------------------------------------------------------
-- Move the cursor so the next item of width w ends at the right edge.
function M.rightAlign(ctx, w)
  local avail = r.ImGui_GetContentRegionAvail(ctx)
  r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + math.max(0, avail - w))
end
function M.vspace(ctx, px) r.ImGui_Dummy(ctx, 0, px or 6) end
function M.hspace(ctx, px) r.ImGui_SameLine(ctx, 0, px or 12) end

-- Leave exactly `px` of space at the bottom (e.g. for ui.status) by eating
-- whatever is left above it. Call just before ui.status when the body is short.
function M.pushToBottom(ctx, px)
  local _, avail = r.ImGui_GetContentRegionAvail(ctx)
  local extra = S(ctx).logOpen and 150 or 0
  if avail > px + extra then r.ImGui_Dummy(ctx, 0, avail - px - extra) end
end

-- Key/value line: label muted, value normal.
function M.kv(ctx, k, v, colour)
  r.ImGui_TextColored(ctx, M.tokens.muted, k); r.ImGui_SameLine(ctx, 0, 6)
  if colour then r.ImGui_TextColored(ctx, colour, v) else r.ImGui_Text(ctx, v) end
end

return M
