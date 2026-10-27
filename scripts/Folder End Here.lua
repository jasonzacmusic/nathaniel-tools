-- @description Folder End Here (the selected track becomes the last track of its folder)
-- @version 1.0.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @about
--   Fixes the "next submix got swallowed" problem in one key press.
--   Select the track that SHOULD be the last one in its folder and run this:
--   the folder closes right after it, the next track or submix pops out one
--   level, and everything further down keeps its exact shape (the track that
--   used to close the folder closes one level less). Press again to pop the
--   next track out one more level. Cmd+Z undoes it.
--   A folder track itself is ignored; select its last child instead.
-- @changelog
--   1.0.0 - first version.

local r = reaper
local proj = 0
local nsel = r.CountSelectedTracks(proj)
if nsel == 0 then return end

local function depth(i) return r.GetMediaTrackInfo_Value(r.GetTrack(proj, i), "I_FOLDERDEPTH") end
local function setd(i, v) r.SetMediaTrackInfo_Value(r.GetTrack(proj, i), "I_FOLDERDEPTH", v) end

-- work bottom-up so earlier fixes don't shift later ones
local idx = {}
for s = 0, nsel - 1 do idx[#idx + 1] = math.floor(r.GetMediaTrackInfo_Value(r.GetSelectedTrack(proj, s), "IP_TRACKNUMBER")) - 1 end
table.sort(idx, function(a, b) return a > b end)

r.Undo_BeginBlock2(proj); r.PreventUIRefresh(1)
local n = r.CountTracks(proj)
for _, x in ipairs(idx) do
  local lvl = 0
  for i = 0, x - 1 do lvl = lvl + depth(i) end        -- folders open around track x
  local dx = depth(x)
  local after = lvl + dx                               -- level of the next track
  if dx < 1 and after > 0 and x < n - 1 then
    local total = 0
    for i = 0, n - 1 do total = total + depth(i) end   -- > 0 means a folder was left open at the end
    setd(x, dx - 1)
    -- the track that used to close this folder now closes one level less
    local l = after
    for y = x + 1, (total > 0) and -1 or (n - 1) do
      l = l + depth(y)
      if l < after then setd(y, depth(y) + 1) break end
    end
  end
end
r.PreventUIRefresh(-1); r.TrackList_AdjustWindows(false); r.UpdateArrange()
r.Undo_EndBlock2(proj, "Folder End Here", -1)
