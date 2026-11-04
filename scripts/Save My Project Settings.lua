-- @description Save My Project Settings (this project's settings become the ones every project gets)
-- @version 1.0.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about
--   Save the front project first, then run this. Its File > Project settings (sample rate, recording,
--   item mixing, crossfades, grid, timebase, pan law, metronome...) become the set that
--   "My Project Settings" gives every project from now on. Restart REAPER to pick it up.
-- @changelog
--   1.0.0 - first version.

local r = reaper
local out = r.GetResourcePath() .. "/Scripts/Nathaniel Tools/data/My Project Settings.txt"
local proj, path = r.EnumProjects(-1)
if path == "" then r.ShowMessageBox("Save this project first, then run this again.", "My Project Settings", 0) return end
if r.IsProjectDirty(proj) ~= 0 then r.ShowMessageBox("This project has unsaved changes. Save it first, then run this again.", "My Project Settings", 0) return end
local f = io.open(path, "rb"); if not f then return end
local lines, depth, keep = {}, 0, {}
for line in f:lines() do
  local s = line:match("^%s*(.-)%s*$")
  if depth == 1 and s:match("^<TRACK") then break end
  if s:sub(1, 1) == "<" then depth = depth + 1 elseif s == ">" then depth = depth - 1 end
  lines[#lines + 1] = line
end
f:close()
r.RecursiveCreateDirectory(out:match("^(.*)/"), 0)
local old = io.open(out, "rb")
if old then local b = io.open(out .. ".previous", "wb"); b:write(old:read("*a")); b:close(); old:close() end
local w = io.open(out, "wb")
w:write("-- saved from " .. path .. " on " .. os.date("%Y-%m-%d %H:%M") .. "\n")
w:write(table.concat(lines, "\n") .. "\n>\n")
w:close()
r.ShowMessageBox("Saved. From the next REAPER start, every project gets these project settings.", "My Project Settings", 0)
