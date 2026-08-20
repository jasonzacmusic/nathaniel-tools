-- @description Open Dock (all the Nathaniel Tools apps, docked)
-- @version 1.2.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about
--   Opens Palette & Look, Folders & Flow, Track Settings Transfer, Stem Print &
--   Handoff, MIDI Batch Export, Group Deck and the Click Strip in REAPER's
--   docker, as tabs, in one go. Run it
--   once from the Actions list, or put it in your startup so the tools are there
--   "at the word go". Apps that are already open are left alone.
--   StageRig is deliberately not included - it is a stage tool, not a studio one.
-- @changelog
--   1.2.0 - also opens the Click Strip.
--   1.1.0 - also opens Group Deck.
--   1.0.0 - first version.

local r = reaper
local base = r.GetResourcePath() .. "/Scripts/Nathaniel Tools/"
local APPS = {
  "apps/Palette and Look.lua",
  "scripts/Folders and Flow.lua",
  "apps/Track Settings Transfer.lua",
  "apps/Stem Print and Handoff.lua",
  "scripts/MIDI Batch Export.lua",
  "apps/Group Deck.lua",
  "apps/Click Strip.lua",
}
local opened, missing = 0, {}
for _, rel in ipairs(APPS) do
  local path = base .. rel
  local fh = io.open(path, "r")
  if fh then
    fh:close()
    -- ask each window to dock on this launch (their Dock toggle remembers afterwards)
    local title = rel:match("([^/]+)%.lua$"):gsub(" and ", " & ")
    -- The Click Strip is a one-line bar, not a page: docking it would bury the
    -- click level behind seven other tabs. It places itself.
    if title ~= "Click Strip" then
      r.SetExtState("NT_UI", "dock:" .. title, "1", true)
    end
    local cmd = r.AddRemoveReaScript(true, 0, path, true)
    if cmd and cmd ~= 0 then
      -- re-running an app that is already open would pop REAPER's "task control"
      -- dialog; nt_ui writes a heartbeat every second, so skip live ones.
      local beat = tonumber(r.GetExtState("NT_UI", "alive:" .. title)) or 0
      if os.time() - beat > 3 then r.Main_OnCommand(cmd, 0); opened = opened + 1 end
    end
  else
    missing[#missing + 1] = rel
  end
end
if #missing > 0 then
  r.ShowMessageBox("Some Nathaniel Tools apps are not installed:\n\n  " .. table.concat(missing, "\n  ") ..
    "\n\nExtensions > ReaPack > Browse packages > right-click Nathaniel Tools > Install All.", "Open Dock", 0)
end
