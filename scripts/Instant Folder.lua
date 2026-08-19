-- @description Instant Folder (new parent above the selected tracks, named and coloured)
-- @version 1.0.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about
--   Select two (or more) tracks and press: a NEW folder track appears above them,
--   the selected tracks go inside it, nothing else in the session changes
--   shape. The folder is named from what the children have in common ("Kick In"
--   + "Kick Out" -> KICK; "Electric L/R/C" -> ELECTRIC), coloured like its
--   children, and made a little taller so it reads as a folder.
--   Non-adjacent selections are first gathered together under the first one.
--   Needs the Shared Libraries package (nt_hierarchy).
-- @changelog
--   1.0.0 - first version.

local r = reaper
do
  local sep = package.config:sub(1, 1)
  local here = ({ r.get_action_context() })[2]:match("(.*" .. sep .. ")") or ""
  package.path = here .. "lib" .. sep .. "?.lua;" .. r.GetResourcePath() .. "/Scripts/Nathaniel Tools/scripts/lib/?.lua;" .. package.path
end
local okH, H = pcall(require, "nt_hierarchy")
if not okH then r.ShowMessageBox("Instant Folder needs the 'Shared Libraries' package (ReaPack > Nathaniel Tools > Install All).", "Instant Folder", 0) return end

local proj = 0
local n = r.CountSelectedTracks(proj)
if n == 0 then r.ShowMessageBox("Select the tracks that should go into the new folder first.", "Instant Folder", 0) return end

r.Undo_BeginBlock2(proj); r.PreventUIRefresh(1)

-- remember the selection by GUID, gather it into one block under the first selected track
local guids, first = {}, nil
for i = 0, n - 1 do
  local t = r.GetSelectedTrack(proj, i)
  guids[#guids + 1] = r.GetTrackGUID(t)
  local idx = math.floor(r.GetMediaTrackInfo_Value(t, "IP_TRACKNUMBER")) - 1
  if not first or idx < first then first = idx end
end
-- contiguous? (every selected index within first..first+n-1)
local contiguous = true
for i = 0, n - 1 do
  local idx = math.floor(r.GetMediaTrackInfo_Value(r.GetSelectedTrack(proj, i), "IP_TRACKNUMBER")) - 1
  if idx < first or idx >= first + n then contiguous = false end
end
if not contiguous then r.ReorderSelectedTracks(first, 0) end

-- children (fresh pointers after the reorder), names, colours, heights
local kids = {}
for _, g in ipairs(guids) do
  for i = 0, r.CountTracks(proj) - 1 do local t = r.GetTrack(proj, i); if r.GetTrackGUID(t) == g then kids[#kids + 1] = t end end
end
table.sort(kids, function(a, b) return r.GetMediaTrackInfo_Value(a, "IP_TRACKNUMBER") < r.GetMediaTrackInfo_Value(b, "IP_TRACKNUMBER") end)
local firstIdx = math.floor(r.GetMediaTrackInfo_Value(kids[1], "IP_TRACKNUMBER")) - 1
local lastIdx  = math.floor(r.GetMediaTrackInfo_Value(kids[#kids], "IP_TRACKNUMBER")) - 1

local function nameOf(t) local _, nm = r.GetSetMediaTrackInfo_String(t, "P_NAME", "", false); return nm or "" end
local function words(s)
  local out = {}
  for w in s:gmatch("[%a]+") do out[#out + 1] = w:lower() end
  return out
end
-- folder name: longest common run of leading words; else most common first word; else first child's first word
local names = {}
for _, t in ipairs(kids) do names[#names + 1] = nameOf(t) end
local common = words(names[1])
for i = 2, #names do
  local w = words(names[i]); local k = 0
  while k < #common and k < #w and common[k + 1] == w[k + 1] do k = k + 1 end
  for j = #common, k + 1, -1 do common[j] = nil end
end
local folderName
if #common > 0 then folderName = table.concat(common, " ")
else
  local count = {}
  for _, nm in ipairs(names) do local w = words(nm)[1]; if w then count[w] = (count[w] or 0) + 1 end end
  local best, bestN = nil, 0
  for w, c in pairs(count) do if c > bestN then best, bestN = w, c end end
  folderName = best or "FOLDER"
end
-- drop trailing L / R / C / numbers style words
folderName = folderName:gsub("%s+[lrcLRC]$", ""):gsub("%s+%d+$", "")
if folderName == "" then folderName = "FOLDER" end
folderName = folderName:upper()

-- colour: the colour the children share, else the first child's
local colour = r.GetTrackColor(kids[1])
for _, t in ipairs(kids) do if r.GetTrackColor(t) ~= colour then colour = r.GetTrackColor(kids[1]) break end end
-- height: a touch taller than the children
local hsum = 0
for _, t in ipairs(kids) do hsum = hsum + (r.GetMediaTrackInfo_Value(t, "I_TCPH") or 0) end
local avgH = hsum / #kids

-- insert the parent above the first child, at the first child's level, and wrap
r.InsertTrackInProject(proj, firstIdx, 0)
local parent = r.GetTrack(proj, firstIdx)
local levels = H.readLevels(proj)
local pIdx = firstIdx + 1                         -- 1-based in levels
levels[pIdx] = levels[pIdx + 1]                   -- same level as the first child
-- wrap exactly the children (and their own subtrees): from the parent to the end of the last child's subtree
local lastChild1 = lastIdx + 2                    -- shifted by the insert, 1-based
local sub = H.subtree(levels, lastChild1)
local toIdx = sub[#sub] or lastChild1
H.makeFolder(levels, pIdx, toIdx)
H.writeLevels(proj, levels)

r.GetSetMediaTrackInfo_String(parent, "P_NAME", folderName, true)
if colour and colour ~= 0 then r.SetTrackColor(parent, colour) end
if avgH > 0 then r.SetMediaTrackInfo_Value(parent, "I_HEIGHTOVERRIDE", math.floor(avgH * 1.25 + 0.5)) end
-- select only the new folder so the next key acts on it
for i = 0, r.CountTracks(proj) - 1 do r.SetTrackSelected(r.GetTrack(proj, i), false) end
r.SetTrackSelected(parent, true)

r.PreventUIRefresh(-1)
r.TrackList_AdjustWindows(false); r.UpdateArrange()
r.Undo_EndBlock2(proj, "Instant folder: " .. folderName, -1)
r.Help_Set(("Instant folder %s over %d tracks"):format(folderName, #kids), false)
