-- @description Rename Colour (background: a Shift-D copy renamed to something new gets its own colour)
-- @version 1.0.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about
--   Runs quietly in the background, next to Duplicate Track.
--   Duplicate Track marks every copy it makes with the name it came from ("Verse").
--   Rename that copy to something new ("Off Beat 1") and it gets a fresh colour, picked to stand
--   apart from every colour already in the project. Renaming within the family (Verse 2 -> Verse 4)
--   keeps the colour. Each copy is recoloured once; after that the colour is yours.
--   Run the action again to switch it off.
-- @changelog
--   1.0.0 - first version.

local r = reaper
local _, _, sec, cmd = r.get_action_context()
if r.set_action_options then r.set_action_options(1) end

local KEY = "P_EXT:nt_dup_base"
local function family(name) return (name:gsub("%s*%d+$", "")):lower() end

local function rgbOf(native) local cr, cg, cb = r.ColorFromNative(native & 0xFFFFFF) return cr, cg, cb end

local function hsv(h, s, v)
  local i = math.floor(h * 6); local f = h * 6 - i
  local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
  local m = i % 6
  local rr, gg, bb
  if m == 0 then rr, gg, bb = v, t, p elseif m == 1 then rr, gg, bb = q, v, p elseif m == 2 then rr, gg, bb = p, v, t
  elseif m == 3 then rr, gg, bb = p, q, v elseif m == 4 then rr, gg, bb = t, p, v else rr, gg, bb = v, p, q end
  return math.floor(rr * 255 + 0.5), math.floor(gg * 255 + 0.5), math.floor(bb * 255 + 0.5)
end

-- a colour as far as possible from every track colour already in the project
local function freshColour(proj)
  local used = {}
  for i = 0, r.CountTracks(proj) - 1 do
    local c = r.GetMediaTrackInfo_Value(r.GetTrack(proj, i), "I_CUSTOMCOLOR")
    if c & 0x1000000 ~= 0 then used[#used + 1] = { rgbOf(c) } end
  end
  local best, bestD
  for _ = 1, 60 do
    local cr, cg, cb = hsv(math.random(), 0.45 + math.random() * 0.3, 0.7 + math.random() * 0.2)
    local d = math.huge
    for _, u in ipairs(used) do
      local dd = (cr - u[1]) ^ 2 + (cg - u[2]) ^ 2 + (cb - u[3]) ^ 2
      if dd < d then d = dd end
    end
    if not bestD or d > bestD then best, bestD = { cr, cg, cb }, d end
  end
  return r.ColorToNative(best[1], best[2], best[3]) | 0x1000000
end

math.randomseed(math.floor(r.time_precise() * 1000))
local nextCheck = 0
local function loop()
  local now = r.time_precise()
  if now >= nextCheck then
    nextCheck = now + 0.4
    local proj = r.EnumProjects(-1)
    for i = 0, r.CountTracks(proj) - 1 do
      local tr = r.GetTrack(proj, i)
      local ok, base = r.GetSetMediaTrackInfo_String(tr, KEY, "", false)
      if ok and base ~= "" then
        local _, name = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
        if name ~= "" and family(name) ~= base then
          r.Undo_BeginBlock2(proj)
          r.SetMediaTrackInfo_Value(tr, "I_CUSTOMCOLOR", freshColour(proj))
          r.GetSetMediaTrackInfo_String(tr, KEY, "", true)
          r.Undo_EndBlock2(proj, "Rename Colour: new colour for " .. name, 1)
        end
      end
    end
  end
  r.defer(loop)
end

r.SetToggleCommandState(sec, cmd, 1); r.RefreshToolbar2(sec, cmd)
r.atexit(function() r.SetToggleCommandState(sec, cmd, 0); r.RefreshToolbar2(sec, cmd) end)
loop()
