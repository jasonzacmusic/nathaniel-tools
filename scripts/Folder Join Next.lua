-- @description Folder Join Next (pull the next track or submix into the selected track's folder)
-- @version 1.0.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @about
--   The opposite of Folder End Here. Select the last track of a folder and run
--   this: the very next track (or the whole next submix, with all its tracks)
--   moves inside that folder, and the folder now ends after it. Nothing else
--   changes shape. Cmd+Z undoes it.
-- @changelog
--   1.0.0 - first version.

local r = reaper
local proj = 0
local sel = r.GetSelectedTrack(proj, 0)
if not sel then return end
local function depth(i) return r.GetMediaTrackInfo_Value(r.GetTrack(proj, i), "I_FOLDERDEPTH") end
local function setd(i, v) r.SetMediaTrackInfo_Value(r.GetTrack(proj, i), "I_FOLDERDEPTH", v) end

local x = math.floor(r.GetMediaTrackInfo_Value(sel, "IP_TRACKNUMBER")) - 1
local n = r.CountTracks(proj)
local dx = depth(x)
if dx >= 0 or x >= n - 1 then return end              -- it doesn't close a folder, or nothing follows

local lvl = 0
for i = 0, x do lvl = lvl + depth(i) end              -- level of the next track, today
-- find the end of the next block: the next track itself, or the last track of the next submix
local e, l = x + 1, lvl
for y = x + 1, n - 1 do
  l = l + depth(y)
  e = y
  if l <= lvl then break end
end

r.Undo_BeginBlock2(proj); r.PreventUIRefresh(1)
setd(x, dx + 1)
setd(e, depth(e) - 1)
r.PreventUIRefresh(-1); r.TrackList_AdjustWindows(false); r.UpdateArrange()
r.Undo_EndBlock2(proj, "Folder Join Next", -1)
