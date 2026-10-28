-- @description Duplicate Track
-- @version 1.3.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about Duplicate the selected track EMPTY and armed, ready to record the next layer; the original is disarmed, every other track keeps its arm state. The copy takes the next number: Verse 1 -> Verse 2, V1 -> V2, O1 -> O2 (skipping numbers already used; "Verse" -> "Verse 2"). Needs SWS.
-- @changelog
--   1.3.0 - the copy is numbered; a copy renamed to something new gets its own colour (with Rename Colour running);: Verse 1 -> Verse 2, V1 -> V2, Take 09 -> Take 10; never repeats a name already in the project.
--   1.2.0 - the track you duplicated is DISARMED; only the new layer is armed. Other tracks untouched.
--   1.1.0 - stops with a message if SWS is missing.
--   1.0.0 - first public release.

-- Duplicate Track (empty)
-- Replaces "Custom: Duplicate Track".  Step 8 of the old chain was 40065
-- "Envelope: Clear or remove envelope", which only ever touched the ONE selected
-- envelope -- so duplicated tracks kept all their automation.
-- It also relied on 40771 (toggle ALL track grouping) netting out to its original
-- state, which only holds if grouping happened to start enabled.
--
-- Result: same FX, routing, name and colour; no items, no automation; armed and
-- ready to record.
if not reaper.NamedCommandLookup("_S&M_WNCLS5") or reaper.NamedCommandLookup("_S&M_WNCLS5") == 0 then
  reaper.ShowMessageBox("Duplicate Track needs the SWS extension (sws-extension.org). Install it and restart REAPER.", "Duplicate Track", 0) return
end
local r = reaper

-- "Verse 1" -> "Verse 2", "V1" -> "V2", "Take 09" -> "Take 10"; no number -> "Verse 2".
-- Picks one past the highest number already used with that same name, so it never repeats.
local function nextName(name, proj)
  local base, num = name:match("^(.-)(%d+)$")
  if not base or base == "" then base, num = name .. " ", "1" end
  local width = #num
  local top = tonumber(num)
  for i = 0, r.CountTracks(proj) - 1 do
    local _, nm = r.GetSetMediaTrackInfo_String(r.GetTrack(proj, i), "P_NAME", "", false)
    if nm:sub(1, #base) == base then
      local n = nm:sub(#base + 1):match("^(%d+)$")
      if n and tonumber(n) > top then top = tonumber(n) end
    end
  end
  return base .. string.format("%0" .. width .. "d", top + 1)
end

local sel = {}
local srcGuid = {}   -- the tracks being duplicated: they hand their arm to the new layer
for i = 0, r.CountSelectedTracks(0) - 1 do
  local t = r.GetSelectedTrack(0, i); sel[#sel+1] = t; srcGuid[r.GetTrackGUID(t)] = true
end
if #sel == 0 then return end

r.Undo_BeginBlock2(0)
r.PreventUIRefresh(1)

local grouping = r.GetToggleCommandState(40771) == 1
if grouping then r.Main_OnCommand(40771, 0) end                 -- suspend grouping

r.Main_OnCommand(r.NamedCommandLookup("_S&M_WNCLS5"), 0)        -- close floating FX for sel

-- FIX: this used to clear I_RECARM on EVERY track in the project and never put
-- it back.  The intent was only to stop the duplicate inheriting record-arm, but
-- the side effect was disarming the whole session - in a 452-track live rig that
-- silently destroys the record setup, and nothing tells you it happened.
-- Snapshot the arm state by GUID, disarm, then restore everything that was not
-- created by this script.
local armWas = {}
for i = 0, r.CountTracks(0) - 1 do
  local tr = r.GetTrack(0, i)
  if tr then
    armWas[r.GetTrackGUID(tr)] = r.GetMediaTrackInfo_Value(tr, "I_RECARM")
    r.SetMediaTrackInfo_Value(tr, "I_RECARM", 0)
  end
end

r.Main_OnCommand(40062, 0)                                      -- Track: Duplicate tracks

-- selection is now the duplicates
local dup = {}
for i = 0, r.CountSelectedTracks(0) - 1 do dup[#dup+1] = r.GetSelectedTrack(0, i) end

for _, tr in ipairs(dup) do
  if r.ValidatePtr2(0, tr, "MediaTrack*") then
    for i = r.CountTrackMediaItems(tr) - 1, 0, -1 do
      r.DeleteTrackMediaItem(tr, r.GetTrackMediaItem(tr, i))
    end
  end
end

r.Main_OnCommand(r.NamedCommandLookup("_S&M_REMOVE_ALLENVS"), 0)

-- put every pre-existing track back exactly as it was...
local isDup = {}
for _, tr in ipairs(dup) do
  if r.ValidatePtr2(0, tr, "MediaTrack*") then isDup[r.GetTrackGUID(tr)] = true end
end
for i = 0, r.CountTracks(0) - 1 do
  local tr = r.GetTrack(0, i)
  if tr then
    local g = r.GetTrackGUID(tr)
    if not isDup[g] and armWas[g] ~= nil then
      -- the source track hands its arm over to the new layer (Jason: "it needs
      -- to unarm the old track"); every other track keeps exactly what it had
      r.SetMediaTrackInfo_Value(tr, "I_RECARM", srcGuid[g] and 0 or armWas[g])
    end
  end
end

-- ...and arm only the new duplicates, which is the point of the script
for _, tr in ipairs(dup) do
  if r.ValidatePtr2(0, tr, "MediaTrack*") then
    r.SetMediaTrackInfo_Value(tr, "I_RECARM", 1)
    r.SetMediaTrackInfo_Value(tr, "I_SOLO", 0)
    r.SetMediaTrackInfo_Value(tr, "B_MUTE", 0)
    local _, nm = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
    if nm ~= "" then
      r.GetSetMediaTrackInfo_String(tr, "P_NAME", nextName(nm, 0), true)
      -- Rename Colour watches this: rename the copy out of its family and it gets its own colour
      r.GetSetMediaTrackInfo_String(tr, "P_EXT:nt_dup_base", (nm:gsub("%s*%d+$", "")):lower(), true)
    end
  end
end

if grouping then r.Main_OnCommand(40771, 0) end                 -- restore grouping

r.Main_OnCommand(r.NamedCommandLookup("_S&M_WNCLS3"), 0)
r.Main_OnCommand(r.NamedCommandLookup("_S&M_WNCLS4"), 0)

r.PreventUIRefresh(-1)
r.Undo_EndBlock2(0, "Duplicate track (empty, armed, next number)", -1)
r.TrackList_AdjustWindows(false)
r.UpdateArrange()
