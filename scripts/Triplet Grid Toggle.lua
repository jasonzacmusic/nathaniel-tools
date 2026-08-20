-- @description Triplet Grid Toggle
-- @version 1.0.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about
--   One button that flips the grid you are already on into triplets, and back.
--   On 1/8? Press it and you are on 1/8 triplets. Press it again and you are
--   back on 1/8. It works from every division, so there is no need for a
--   separate 1/4T, 1/8T and 1/24 button cluttering the bar.
--
--   The button lights up whenever the grid is a triplet division, so you can
--   see at a glance which side you are on.
-- @changelog
--   1.0.0 - first version.

local r = reaper

-- Straight divisions REAPER offers, longest first. A triplet division is any
-- of these times 2/3.
local STRAIGHT = { 4, 2, 1, 1/2, 1/4, 1/8, 1/16, 1/32, 1/64, 1/128 }
local TRIPLET_RATIO = 2 / 3
local TOLERANCE = 1e-6

local function near(a, b)
  return math.abs(a - b) < math.max(TOLERANCE, math.abs(b) * 1e-4)
end

-- Which straight division is this a triplet of? nil when the grid is straight
-- (or something exotic like a quintuplet, which we leave alone).
local function straightBehind(division)
  for _, straight in ipairs(STRAIGHT) do
    if near(division, straight * TRIPLET_RATIO) then return straight end
  end
  return nil
end

local function closestStraight(division)
  local best, bestGap = nil, math.huge
  for _, straight in ipairs(STRAIGHT) do
    local gap = math.abs(math.log(division / straight))
    if gap < bestGap then best, bestGap = straight, gap end
  end
  return best
end

local function currentGrid()
  -- GetSetProjectGrid returns division, swing flag, swing amount.
  local _, division, swingOn, swingAmount = r.GetSetProjectGrid(0, false)
  return division, swingOn, swingAmount
end

local function setGrid(division, swingOn, swingAmount)
  r.GetSetProjectGrid(0, true, division, swingOn, swingAmount)
end

-- Toolbar light: on when the current grid is a triplet.
local function reportToggleState(isTriplet)
  local _, _, section, cmd = r.get_action_context()
  if section and cmd and cmd ~= 0 then
    r.SetToggleCommandState(section, cmd, isTriplet and 1 or 0)
    r.RefreshToolbar2(section, cmd)
  end
end

local function main()
  local division, swingOn, swingAmount = currentGrid()
  if not division or division <= 0 then return end

  local straight = straightBehind(division)
  local target, label

  if straight then
    -- Already triplets - go back to the straight division it came from.
    target = straight
    label = "Grid: straight"
  else
    -- Straight (or an odd value) - snap to the nearest straight division and
    -- make it a triplet, so the button always lands somewhere musical.
    target = closestStraight(division) * TRIPLET_RATIO
    label = "Grid: triplets"
  end

  r.Undo_BeginBlock()
  setGrid(target, swingOn, swingAmount)
  r.Undo_EndBlock(label, -1)

  reportToggleState(straight == nil)
  r.UpdateArrange()
end

main()
