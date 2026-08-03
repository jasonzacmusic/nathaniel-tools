-- @noindex
-- Shared library for the NPH REAPER Suite. Not a standalone action.
-- Distributed by the packages that need it via their @provides tag.

--[[
  nph_imgui.lua  -  ReaImGui version compatibility for the NPH suite
  ----------------------------------------------------------------------------
  WHY THIS FILE EXISTS

  ReaImGui tracks Dear ImGui, and Dear ImGui renames enum constants between
  releases.  When it does, a script written against the old name does not
  degrade gracefully - it throws "attempt to call a nil value" the instant the
  window opens, which to the user looks like "the app is broken", with no clue
  that a dependency moved underneath it.

  Measured on this machine (REAPER 7.28, ReaImGui reporting Dear ImGui 1.92.1)
  by probing every ImGui function the suite calls:

      78 referenced, 76 present, 2 MISSING

      ImGui_Col_TabActive      -> now ImGui_Col_TabSelected
      ImGui_ChildFlags_Border  -> now ImGui_ChildFlags_Borders   (plural)

  Those two would have crashed Palette & Look, Track Settings Transfer and
  Stem Print & Handoff on first open.

  install() aliases every known pair in BOTH directions, so one codebase runs on
  an old ReaImGui and a new one.  Add a row when the next rename lands; do not
  scatter version checks through the apps.
--]]

local r = reaper
local M = {}

-- { name the suite calls, name a newer ReaImGui uses }
local ALIASES = {
  { "ImGui_Col_TabActive",          "ImGui_Col_TabSelected" },
  { "ImGui_Col_TabUnfocused",       "ImGui_Col_TabDimmed" },
  { "ImGui_Col_TabUnfocusedActive", "ImGui_Col_TabDimmedSelected" },
  { "ImGui_ChildFlags_Border",      "ImGui_ChildFlags_Borders" },
}

-- Returns the number of aliases it had to bridge, so a caller (or the harness)
-- can report drift rather than silently paper over it.
function M.install()
  local bridged = 0
  for _, pair in ipairs(ALIASES) do
    local old, new = pair[1], pair[2]
    if r[old] == nil and r[new] ~= nil then
      r[old] = r[new]; bridged = bridged + 1
    elseif r[new] == nil and r[old] ~= nil then
      r[new] = r[old]; bridged = bridged + 1
    end
  end
  return bridged
end

-- Which of the names this suite relies on are missing entirely (i.e. neither
-- the old nor the new spelling exists). Empty table = safe to open a window.
function M.missing()
  local gone = {}
  for _, pair in ipairs(ALIASES) do
    if r[pair[1]] == nil and r[pair[2]] == nil then gone[#gone+1] = pair[1] end
  end
  return gone
end

return M
