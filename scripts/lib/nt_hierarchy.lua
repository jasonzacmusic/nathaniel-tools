-- @noindex
-- Shared library for the Nathaniel Tools. Not a standalone action.
-- Distributed by the packages that need it via their @provides tag.

--[[
  nt_hierarchy.lua  -  folder maths for the Nathaniel Tools
  ----------------------------------------------------------------------------
  THE IDEA THAT MAKES FOLDER EDITING SAFE

  REAPER does not store a tree.  It stores one integer per track, I_FOLDERDEPTH:

      1   this track OPENS a folder (the next track is one level deeper)
      0   this track is a sibling of the one before it
     -n   this track CLOSES n folders after itself

  Editing those integers in place is where every folder script goes wrong: a
  local edit that looks right leaves the arithmetic unbalanced further down, and
  REAPER silently swallows the rest of the session into a folder.  That is not a
  hypothetical - it is the bug the v4 header of Track Settings Transfer calls out.

  So we never edit depths directly.  We convert to LEVELS (0 = root, 1 = inside
  one folder, ...), do the edit on levels where the operation is obvious and
  impossible to get wrong, then regenerate every depth from the levels.

      depths  ->  levels  ->  edit  ->  depths

  Regenerating from levels is total: the output is always well-formed, every
  folder closes, and the last track can never leave one hanging open.  That one
  decision removes the entire class of bug.

  CHANGED WITH FOLDERS & FLOW 2.0.0 (this file is @noindex, so no version bump)
    * selectionRoots() / applyToRoots(): a multi-track Indent / Outdent / Out of
      folder acts on SELECTION ROOTS only - a ticked track whose parent is also
      ticked is skipped, because moving the parent already moves it.  The old
      loop (demote last->first, promote first->last) moved nested selections two
      levels.  Roots are processed first->last, which cannot double-apply.
    * moveLevels(): the pure-Lua plan for "move this folder up/down".  The new
      levels are computed BEFORE the tracks are reordered, then written after,
      so a subtree whose last track closed an outer folder (depth -2) no longer
      drags that closer with it and swallows the neighbour.
    * moveSubtree(): saves and restores the user's track selection (it used to
      deselect everything and leave the subtree selected).
    * isolate() only hides tracks that were visible, and returns the GUIDs it
      hid; showGuids() un-hides exactly those.  Tracks the user hid on purpose
      are never touched.

  Author: Jason Zac / Nathaniel School of Music
--]]

local r = reaper
local M = {}

-- nt_safe is optional here (this file is also loaded by the pure-Lua tests
-- with a fake `reaper`); moveSubtree falls back to a GUID loop without it.
local okSafe, safe = pcall(require, "nt_safe")
if not okSafe then safe = nil end

--------------------------------------------------------------------------------
-- depths  <->  levels
--------------------------------------------------------------------------------

-- Nesting level of every track.  levels[i] is 0-based; index is 1-based Lua.
function M.readLevels(proj)
  local n = r.CountTracks(proj)
  local levels, lvl = {}, 0
  for i = 0, n - 1 do
    levels[i + 1] = lvl
    local t = r.GetTrack(proj, i)
    local d = t and math.floor(r.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH") or 0) or 0
    lvl = lvl + d
    if lvl < 0 then lvl = 0 end
  end
  return levels
end

-- Make a level list legal:
--   * the first track is always at root
--   * a track can be at most ONE level deeper than the track before it
--     (REAPER has no way to express "two levels deeper in one step")
--   * no negative levels
function M.sanitizeLevels(levels)
  if #levels == 0 then return levels end
  levels[1] = 0
  for i = 2, #levels do
    if levels[i] < 0 then levels[i] = 0 end
    if levels[i] > levels[i - 1] + 1 then levels[i] = levels[i - 1] + 1 end
  end
  return levels
end

-- Regenerate every I_FOLDERDEPTH from the levels.  Returns how many changed.
function M.writeLevels(proj, levels)
  M.sanitizeLevels(levels)
  local n = r.CountTracks(proj)
  local changed = 0
  for i = 1, n do
    local t = r.GetTrack(proj, i - 1)
    if t then
      local want
      if i == n then
        want = -levels[i]                    -- last track closes everything still open
      else
        want = levels[i + 1] - levels[i]     -- +1 opens, 0 sibling, -n closes n
        if want > 1 then want = 1 end
      end
      local have = math.floor(r.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH") or 0)
      if have ~= want then
        r.SetMediaTrackInfo_Value(t, "I_FOLDERDEPTH", want)
        changed = changed + 1
      end
    end
  end
  return changed
end

--------------------------------------------------------------------------------
-- tree queries  (all 1-based indices into the levels array)
--------------------------------------------------------------------------------

-- Is track i a folder parent?  True when the next track sits deeper.
function M.isParent(levels, i)
  return levels[i + 1] ~= nil and levels[i + 1] > levels[i]
end

-- Every track belonging to i's subtree, i included.  A subtree is i plus the
-- contiguous run of tracks that are deeper than i.
function M.subtree(levels, i)
  local out = { i }
  local j = i + 1
  while levels[j] ~= nil and levels[j] > levels[i] do
    out[#out + 1] = j
    j = j + 1
  end
  return out
end

-- Index of i's folder parent, or nil at root.
function M.parentOf(levels, i)
  if levels[i] == 0 then return nil end
  for j = i - 1, 1, -1 do
    if levels[j] == levels[i] - 1 then return j end
  end
  return nil
end

--------------------------------------------------------------------------------
-- operations  -  each one edits LEVELS only
--------------------------------------------------------------------------------

-- Demote: push a track (and its subtree) one level deeper, making it a child of
-- whatever sits above it.  Refuses when it would create an illegal jump.
function M.demote(levels, i)
  if i <= 1 then return false, "the first track cannot be indented - there is nothing above it" end
  if levels[i] > levels[i - 1] then return false, "already as deep as it can go under that parent" end
  for _, k in ipairs(M.subtree(levels, i)) do levels[k] = levels[k] + 1 end
  return true
end

-- Promote: pull a track (and its subtree) out one level.
function M.promote(levels, i)
  if levels[i] == 0 then return false, "already at the top level" end
  for _, k in ipairs(M.subtree(levels, i)) do levels[k] = levels[k] - 1 end
  return true
end

-- Take a track out of its folder entirely, back to the root.
function M.toRoot(levels, i)
  if levels[i] == 0 then return false, "already at the top level" end
  local drop = levels[i]
  for _, k in ipairs(M.subtree(levels, i)) do levels[k] = levels[k] - drop end
  return true
end

-- SELECTION ROOTS.  When several tracks are ticked, only the ones whose folder
-- parent (or grand-parent...) is NOT also ticked should be acted on: moving a
-- parent moves its whole subtree, so acting on a ticked child too would move
-- it twice.  Returns the roots in ascending order.
--
-- Subtrees are contiguous, so a ticked track sits inside an earlier ticked
-- root's subtree exactly when its index is <= that root's last subtree index.
function M.selectionRoots(levels, idxs)
  local sorted = {}
  for _, i in ipairs(idxs or {}) do
    if levels[i] ~= nil then sorted[#sorted + 1] = i end
  end
  table.sort(sorted)
  local roots, coverEnd, lastSeen = {}, 0, nil
  for _, i in ipairs(sorted) do
    if i ~= lastSeen and i > coverEnd then
      roots[#roots + 1] = i
      local sub = M.subtree(levels, i)
      coverEnd = sub[#sub]
    end
    lastSeen = i
  end
  return roots
end

-- Apply one of demote / promote / toRoot to every selection root, first to
-- last.  Each root's subtree is a disjoint index range that no earlier root
-- can touch, so every track moves at most once.  (Last-to-first is NOT safe
-- for demote: demoting track 3 first makes it part of track 2's subtree, and
-- demoting track 2 then moves it a second time.)
-- Returns moved, skipped, firstReason, rootCount.
function M.applyToRoots(levels, idxs, op)
  local roots = M.selectionRoots(levels, idxs)
  local moved, skipped, why = 0, 0, nil
  for _, i in ipairs(roots) do
    local ok, err = op(levels, i)
    if ok then moved = moved + 1
    else skipped = skipped + 1; why = why or err end
  end
  return moved, skipped, why, #roots
end

function M.demoteMany(levels, idxs)  return M.applyToRoots(levels, idxs, M.demote)  end
function M.promoteMany(levels, idxs) return M.applyToRoots(levels, idxs, M.promote) end
function M.toRootMany(levels, idxs)  return M.applyToRoots(levels, idxs, M.toRoot)  end

-- Dissolve a folder: the parent stays as an ordinary track, its children move up
-- one level to sit beside it.  Nothing is deleted.
function M.dissolve(levels, i)
  if not M.isParent(levels, i) then return false, "that track is not a folder" end
  local sub = M.subtree(levels, i)
  for idx, k in ipairs(sub) do
    if idx > 1 then levels[k] = levels[k] - 1 end   -- children only, not the parent
  end
  return true
end

-- Make a folder out of a contiguous run: the first track becomes the parent and
-- EXACTLY from..to ends up inside it.
--
-- The naive version of this (just add 1 to each child's level) is wrong whenever
-- the tracks are already nested: the added level gets clamped by sanitize, the
-- folder never closes where you asked, and everything after `to` is silently
-- swallowed into the new folder.  The harness caught exactly that.
--
-- So: shift the children so the shallowest of them sits one below the parent -
-- which preserves any nesting they already had among themselves - and then
-- explicitly pop anything after `to` back out to the parent's level, so the new
-- folder ends where the user said it ends.
function M.makeFolder(levels, from, to)
  if to <= from then return false, "pick at least two tracks to make a folder" end
  if levels[from] == nil or levels[to] == nil then return false, "selection is out of range" end

  local base = levels[from]
  local minChild = math.huge
  for k = from + 1, to do
    if levels[k] < minChild then minChild = levels[k] end
  end
  if minChild == math.huge then return false, "nothing to put in the folder" end

  local shift = (base + 1) - minChild
  for k = from + 1, to do levels[k] = levels[k] + shift end

  -- close the folder at `to`: anything deeper than the parent immediately after
  -- it was inside the old folder and must come back out, or it joins the new one
  local k = to + 1
  while levels[k] ~= nil and levels[k] > base do
    levels[k] = base
    k = k + 1
  end
  return true
end

--------------------------------------------------------------------------------
-- reordering a whole subtree
--   REAPER has no "move this folder and its children" primitive, and
--   _SWS_MOVETRACKUP / _SWS_MOVETRACKDOWN are not present on this install.
--   We select the subtree and use ReorderSelectedTracks, which moves the whole
--   selection as one block.
--
--   ReorderSelectedTracks carries each track's I_FOLDERDEPTH along with it.
--   Depths are relative, so that corrupts the neighbours: a subtree whose last
--   track closed an OUTER folder (-2) takes that closer with it, and the parent
--   it left behind swallows whatever now follows it.  So the new nesting is
--   planned on LEVELS first (moveLevels, pure Lua, tested), the tracks are
--   moved, and the planned levels are written back.
--------------------------------------------------------------------------------

-- Plan a move on levels only.  Returns newLevels, dest  (dest = 0-based
-- "insert before this track index" for ReorderSelectedTracks), or nil, reason.
--
--   up    swap places with the sibling subtree that ends just above; if the
--         track is the FIRST child of its folder it hops out above the parent
--         (becomes the parent's sibling).
--   down  swap places with the sibling subtree that starts just below; if it
--         is the LAST child of its folder it hops out below the folder
--         (becomes a sibling of whatever shallower block it hopped over).
function M.moveLevels(levels, i, dir)
  local n = #levels
  if n == 0 or levels[i] == nil then return nil, "nothing to move" end
  local sub = M.subtree(levels, i)
  local first, last = sub[1], sub[#sub]
  local out = {}
  local function push(a, b, delta)
    for k = a, b do out[#out + 1] = levels[k] + (delta or 0) end
  end
  if dir < 0 then
    if first == 1 then return nil, "already at the top" end
    -- hop over the whole block that ends just above us
    local top = first - 1
    while top > 1 and levels[top] > levels[first] do top = top - 1 end
    -- top is either a sibling root (same level) or our parent (one shallower)
    local delta = levels[top] - levels[first]
    push(1, top - 1)
    push(first, last, delta)
    push(top, first - 1)
    push(last + 1, n)
    return out, top - 1
  else
    if last == n then return nil, "already at the bottom" end
    local below = last + 1
    local bottom = below
    while levels[bottom + 1] ~= nil and levels[bottom + 1] > levels[below] do bottom = bottom + 1 end
    -- below is either a sibling root (same level) or shallower (we leave the folder)
    local delta = levels[below] - levels[first]
    push(1, first - 1)
    push(below, bottom)
    push(first, last, delta)
    push(bottom + 1, n)
    return out, bottom
  end
end

local function saveSel(proj)
  if safe then return safe.saveSelection(proj) end
  local s = {}
  for k = 0, r.CountSelectedTracks(proj) - 1 do
    local t = r.GetSelectedTrack(proj, k)
    if t then s[r.GetTrackGUID(t)] = true end
  end
  return s
end
local function restoreSel(proj, saved)
  if safe then return safe.restoreSelection(proj, saved) end
  for k = 0, r.CountTracks(proj) - 1 do
    local t = r.GetTrack(proj, k)
    if t then r.SetMediaTrackInfo_Value(t, "I_SELECTED", saved[r.GetTrackGUID(t)] and 1 or 0) end
  end
end

function M.moveSubtree(proj, i, dir)
  local levels = M.readLevels(proj)
  local n = #levels
  if n == 0 then return false, "nothing to move" end
  local plan, dest = M.moveLevels(levels, i, dir)
  if not plan then return false, dest end
  if dest < 0 then dest = 0 end
  local sub = M.subtree(levels, i)

  local saved = saveSel(proj)

  -- select exactly the subtree and move it as one block
  for k = 0, n - 1 do
    local t = r.GetTrack(proj, k)
    if t then r.SetMediaTrackInfo_Value(t, "I_SELECTED", 0) end
  end
  for _, k in ipairs(sub) do
    local t = r.GetTrack(proj, k - 1)
    if t then r.SetMediaTrackInfo_Value(t, "I_SELECTED", 1) end
  end
  r.ReorderSelectedTracks(dest, 0)

  -- write the nesting we planned; if the track count somehow changed under
  -- us, at least make the arithmetic well-formed from what is there
  if r.CountTracks(proj) == #plan then
    M.writeLevels(proj, plan)
  else
    M.writeLevels(proj, M.readLevels(proj))
  end

  restoreSel(proj, saved)
  return true
end

--------------------------------------------------------------------------------
-- auto-build folders from track names
--   Groups consecutive root-level tracks that share a leading token, so
--   "Kick In / Kick Out / Snare Top / Snare Btm" becomes two folders.
--   Only ever groups tracks that are ALREADY adjacent - it never reorders your
--   session behind your back.
--------------------------------------------------------------------------------

local function leadToken(name)
  local w = (name or ""):lower():match("^%s*([%a]+)")
  return w
end

function M.autoGroupPlan(proj, minSize)
  minSize = minSize or 2
  local levels = M.readLevels(proj)
  local n = #levels
  local plan = {}
  local i = 1
  while i <= n do
    if levels[i] ~= 0 then i = i + 1
    else
      local t = r.GetTrack(proj, i - 1)
      local _, nm = r.GetSetMediaTrackInfo_String(t, "P_NAME", "", false)
      local tok = leadToken(nm)
      if not tok then i = i + 1
      else
        local j = i
        while j + 1 <= n and levels[j + 1] == 0 do
          local t2 = r.GetTrack(proj, j)
          local _, nm2 = r.GetSetMediaTrackInfo_String(t2, "P_NAME", "", false)
          if leadToken(nm2) ~= tok then break end
          j = j + 1
        end
        if (j - i + 1) >= minSize then
          plan[#plan + 1] = { from = i, to = j, token = tok, count = j - i + 1 }
          i = j + 1
        else
          i = i + 1
        end
      end
    end
  end
  return plan
end

--------------------------------------------------------------------------------
-- focus / isolate
--------------------------------------------------------------------------------

function M.setVisible(proj, wanted)
  local n = r.CountTracks(proj)
  for i = 0, n - 1 do
    local t = r.GetTrack(proj, i)
    if t then
      local on = (wanted == nil) and 1 or (wanted[i + 1] and 1 or 0)
      r.SetMediaTrackInfo_Value(t, "B_SHOWINTCP", on)
      r.SetMediaTrackInfo_Value(t, "B_SHOWINMIXER", on)
    end
  end
  r.TrackList_AdjustWindows(false)
end

-- Show only track i's subtree (plus its ancestors, so you can see where you
-- are).  Only tracks that were VISIBLE get hidden, and their GUIDs are
-- returned so the caller can un-hide exactly those later.  Tracks the user
-- had already hidden are left alone and not reported.
function M.isolate(proj, i)
  local levels = M.readLevels(proj)
  local want = {}
  for _, k in ipairs(M.subtree(levels, i)) do want[k] = true end
  local p = M.parentOf(levels, i)
  while p do want[p] = true; p = M.parentOf(levels, p) end

  local hidden = {}
  local n = r.CountTracks(proj)
  for k = 0, n - 1 do
    local t = r.GetTrack(proj, k)
    if t then
      if want[k + 1] then
        r.SetMediaTrackInfo_Value(t, "B_SHOWINTCP", 1)
        r.SetMediaTrackInfo_Value(t, "B_SHOWINMIXER", 1)
      else
        local tcp = r.GetMediaTrackInfo_Value(t, "B_SHOWINTCP") or 0
        local mcp = r.GetMediaTrackInfo_Value(t, "B_SHOWINMIXER") or 0
        if tcp ~= 0 or mcp ~= 0 then
          hidden[#hidden + 1] = r.GetTrackGUID(t)
          r.SetMediaTrackInfo_Value(t, "B_SHOWINTCP", 0)
          r.SetMediaTrackInfo_Value(t, "B_SHOWINMIXER", 0)
        end
      end
    end
  end
  r.TrackList_AdjustWindows(false)
  return hidden
end

-- Un-hide exactly the tracks whose GUID is in `set` ([guid]=true).
-- Returns how many tracks were shown again.
function M.showGuids(proj, set)
  local shown = 0
  if not set then return 0 end
  local n = r.CountTracks(proj)
  for k = 0, n - 1 do
    local t = r.GetTrack(proj, k)
    if t and set[r.GetTrackGUID(t)] then
      r.SetMediaTrackInfo_Value(t, "B_SHOWINTCP", 1)
      r.SetMediaTrackInfo_Value(t, "B_SHOWINMIXER", 1)
      shown = shown + 1
    end
  end
  r.TrackList_AdjustWindows(false)
  return shown
end

-- Everything visible again (kept for callers that really want everything).
function M.showAll(proj) M.setVisible(proj, nil) end

return M
