-- @description Shared Libraries
-- @version 1.2.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @provides
--   [nomain] lib/nt_safe.lua
--   [nomain] lib/nt_hierarchy.lua
--   [nomain] lib/nt_imgui.lua
--   [nomain] lib/nt_ui.lua
-- @about
--   The shared code the rest of the Nathaniel Tools is built on: pointer safety and
--   stable track identity (nt_safe), folder-nesting arithmetic (nt_hierarchy),
--   and ReaImGui version compatibility (nt_imgui).
--
--   INSTALL THIS FIRST. Most apps in the suite will not run without it.
--   ReaPack has no automatic dependency resolution, and it gives each package
--   exclusive ownership of the files it installs - so these libraries cannot be
--   shipped inside every app that needs them. They live here instead.
--
--   The easiest route is to install the whole repository at once: right-click
--   "Nathaniel Tools" in ReaPack's package browser and choose Install All.
--
--   Running this script is optional. It just reports which libraries are
--   present and what version they are, which is the first thing worth knowing
--   when an app misbehaves.
-- @changelog
--   1.2.0 - windows open docked by default and remember the Dock toggle; heartbeat for Open Dock.
--   1.1.0 - adds nt_ui, the shared design system every window now uses.
--   1.0.0 - split out of the individual app packages so every app can share one
--           copy instead of each carrying its own.

local r = reaper

local sep = package.config:sub(1, 1)
local here = ({r.get_action_context()})[2]:match("(.*" .. sep .. ")") or ""
package.path = here .. "lib" .. sep .. "?.lua;" .. package.path

local LIBS = {
  { "nt_safe",      "pointer safety and stable track identity" },
  { "nt_hierarchy", "folder nesting arithmetic" },
  { "nt_imgui",     "ReaImGui version compatibility" },
  { "nt_ui",        "the shared look: theme, fonts, header, buttons, tables, status" },
}

local lines = { "Shared Libraries", "" }
local missing = 0

for _, entry in ipairs(LIBS) do
  local name, what = entry[1], entry[2]
  local ok, mod = pcall(require, name)
  if ok and type(mod) == "table" then
    lines[#lines + 1] = ("  OK       %-16s %s"):format(name, what)
  else
    missing = missing + 1
    lines[#lines + 1] = ("  MISSING  %-16s %s"):format(name, what)
  end
end

lines[#lines + 1] = ""
lines[#lines + 1] = "installed at: " .. here .. "lib" .. sep

if missing == 0 then
  lines[#lines + 1] = "All libraries present. Every app in the suite can run."
else
  lines[#lines + 1] = missing .. " missing. Reinstall this package from ReaPack:"
  lines[#lines + 1] = "Extensions > ReaPack > Browse packages > Shared Libraries."
end

-- Environment, because it is what the answer usually turns on.
lines[#lines + 1] = ""
lines[#lines + 1] = "REAPER:   " .. tostring(r.GetAppVersion())
lines[#lines + 1] = "ReaImGui: " ..
  (r.ImGui_CreateContext and "present" or "NOT INSTALLED - the windowed apps need it")
lines[#lines + 1] = "SWS:      " ..
  (r.BR_GetMediaTrackSendInfo_Track and "present" or "not installed (optional)")

r.ShowMessageBox(table.concat(lines, "\n"), "Shared Libraries", 0)
