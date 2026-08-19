-- Load the real module with a fake `reaper` so the pure maths can be tested.
reaper = { CountTracks=function() return 0 end, GetTrack=function() return nil end,
           GetMediaTrackInfo_Value=function() return 0 end, SetMediaTrackInfo_Value=function() end,
           GetSetMediaTrackInfo_String=function() return true,"" end,
           ReorderSelectedTracks=function() end, TrackList_AdjustWindows=function() end }
-- Resolve the library relative to this file, so the suite runs from any clone.
local here = (debug.getinfo(1, "S").source:sub(2)):match("(.*/)") or "./"
package.path = here .. "../scripts/lib/?.lua;" .. package.path
local H = require("nt_hierarchy")

local pass, fail = 0, 0
local function ck(cond, label)
  if cond then pass=pass+1; print("PASS  "..label)
  else fail=fail+1; print("FAIL  "..label) end
end
local function eq(a,b) if #a~=#b then return false end for i=1,#a do if a[i]~=b[i] then return false end end return true end
local function show(t) return "{"..table.concat(t,",").."}" end

-- levels -> depths, computed the same way writeLevels does
local function depthsFrom(levels)
  local n=#levels; local d={}
  for i=1,n do
    if i==n then d[i] = -levels[i]
    else local w = levels[i+1]-levels[i]; if w>1 then w=1 end; d[i]=w end
  end
  return d
end
-- depths -> levels, the same way readLevels does
local function levelsFrom(depths)
  local lvl,out=0,{}
  for i=1,#depths do out[i]=lvl; lvl=lvl+depths[i]; if lvl<0 then lvl=0 end end
  return out
end

print("== round trip ==")
local cases = {
  {0,0,0},              -- flat
  {0,1,1,0},            -- one folder with two children
  {0,1,2,2,1,0},        -- nested two deep
  {0,1,1,1,1,1},        -- folder running to the end (the classic hang-open case)
}
for _,lv in ipairs(cases) do
  local d = depthsFrom(lv)
  local back = levelsFrom(d)
  ck(eq(lv, back), "levels "..show(lv).." -> depths "..show(d).." -> levels "..show(back))
end

print("\n== every folder closes ==")
for _,lv in ipairs(cases) do
  local d = depthsFrom(lv)
  local sum=0; for i=1,#d do sum=sum+d[i] end
  ck(sum==0, "depths sum to zero for "..show(lv).."  (nothing left hanging open)")
end

print("\n== sanitize ==")
local bad = {0,3,1}                        -- illegal: jumps 3 deep in one step
H.sanitizeLevels(bad)
ck(eq(bad,{0,1,1}), "illegal jump clamped: got "..show(bad))
local bad2 = {2,2}                          -- illegal: first track not at root
H.sanitizeLevels(bad2)
ck(bad2[1]==0, "first track forced to root")
local bad3 = {0,-4,0}
H.sanitizeLevels(bad3)
ck(bad3[2]>=0, "negative level clamped")

print("\n== subtree / parent ==")
local lv = {0,1,2,2,1,0}   -- 1 is parent; 2 is a sub-folder holding 3,4; 5 sibling of 2; 6 root
ck(H.isParent(lv,1)==true,  "track 1 is a folder parent")
ck(H.isParent(lv,3)==false, "track 3 is not a parent")
ck(eq(H.subtree(lv,1),{1,2,3,4,5}), "subtree of 1 = "..show(H.subtree(lv,1)))
ck(eq(H.subtree(lv,2),{2,3,4}),     "subtree of 2 = "..show(H.subtree(lv,2)))
ck(H.parentOf(lv,3)==2, "parent of 3 is 2")
ck(H.parentOf(lv,1)==nil, "track 1 has no parent")

print("\n== operations ==")
local a = {0,1,1,0}
ck(H.promote(a,2)==true and a[2]==0, "promote pulls a child to root")
local b = {0,0,0}
ck(H.demote(b,2)==true and b[2]==1, "demote makes track 2 a child of 1")
local c = {0,0}
ck(H.demote(c,1)==false, "cannot indent the very first track")
local d2 = {0,1,2,1,0}
ck(H.toRoot(d2,3)==true and d2[3]==0, "out-of-folder sends a deep track to root")
local e = {0,1,1,0}
ck(H.dissolve(e,1)==true and e[2]==0 and e[3]==0, "dissolve promotes children, keeps the parent")
local f = {0,0,0}
ck(H.makeFolder(f,1,3)==true and f[2]==1 and f[3]==1, "makeFolder nests the run under the first")
local g = {0,0}
ck(H.makeFolder(g,1,1)==false, "makeFolder refuses a single track")

print("\n== the hang-open bug cannot be reproduced ==")
-- take a folder that runs to the very end and confirm the last depth closes it
local run = {0,1,1,1}
local dd = depthsFrom(run)
ck(dd[#dd] == -1, "last track closes the folder (depth "..dd[#dd]..")")
local sum=0; for i=1,#dd do sum=sum+dd[i] end
ck(sum==0, "and the whole thing balances")

print("\n== makeFolder on ALREADY-NESTED tracks (the bug the harness caught) ==")
-- DRUMS folder currently holds everything: {0,1,1,1,1}
local nest = {0,1,1,1,1}
local ok = H.makeFolder(nest, 1, 3)
ck(ok == true, "makeFolder accepted")
ck(eq(nest, {0,1,1,0,0}), "folder now ends at track 3: got "..show(nest))
ck(#H.subtree(nest,1) == 3, "subtree of the folder is exactly 3 tracks")
ck(H.isParent(nest,4) == false, "track 4 popped out and is not a parent")
local dn = depthsFrom(nest); local s2=0; for i=1,#dn do s2=s2+dn[i] end
ck(s2 == 0, "depths still balance")

print("\n== selection roots (multi-track indent/outdent act on roots only) ==")
-- {0,1,2,2,1,0}: 1 holds 2..5; 2 holds 3,4; 5 is 2's sibling; 6 root
local sr = {0,1,2,2,1,0}
ck(eq(H.selectionRoots(sr,{1,2,3,5,6}),{1,6}), "ticked parent + children -> only the parent and the outsider are roots")
ck(eq(H.selectionRoots(sr,{2,3,5}),{2,5}),     "ticked sub-folder + its child + a sibling -> {2,5}")
ck(eq(H.selectionRoots(sr,{4,3}),{3,4}),       "two plain siblings are both roots, returned in order")
ck(eq(H.selectionRoots(sr,{}),{}),             "nothing ticked -> no roots")
ck(eq(H.selectionRoots(sr,{3,3,3}),{3}),       "duplicates collapse to one root")

print("\n== multi-track Indent cannot move a track twice (the audit bug) ==")
-- flat, tick 2 and 3: old last->first loop gave {0,1,2,0}; each should move ONE level
local m1 = {0,0,0,0}
local moved, skipped = H.demoteMany(m1, {2,3})
ck(eq(m1,{0,1,1,0}) and moved == 2, "flat: tick 2,3 -> both one level deeper: got "..show(m1))
-- 2 is a folder holding 3 and 4 (siblings); tick all three: only 2 is a root
local m2 = {0,0,1,1}
moved, skipped = H.demoteMany(m2, {2,3,4})
ck(eq(m2,{0,1,2,2}) and moved == 1 and skipped == 0, "nested selection: whole subtree moves once: got "..show(m2))
-- first track can never indent; the reason comes back
local m3 = {0,0}
moved, skipped = H.demoteMany(m3, {1,2})
ck(moved == 1 and skipped == 1 and eq(m3,{0,1}), "first track skipped with a reason, second still indents")

print("\n== multi-track Outdent cannot move a track twice (the mirror bug) ==")
-- 1 > 2 > 3 ; tick 2 and 3: old first->last loop gave {0,0,0}
local o1 = {0,1,2}
moved = H.promoteMany(o1, {2,3})
ck(eq(o1,{0,0,1}) and moved == 1, "nested selection outdents as one block: got "..show(o1))
local o2 = {0,1,1}
moved = H.promoteMany(o2, {2,3})
ck(eq(o2,{0,0,0}) and moved == 2, "two siblings each come out one level: got "..show(o2))

print("\n== multi-track Out of folder keeps the inner nesting ==")
local t1 = {0,1,2,3}
moved = H.toRootMany(t1, {2,3,4})
ck(eq(t1,{0,0,1,2}) and moved == 1, "ticked folder + descendants -> folder to root, children keep shape: got "..show(t1))

print("\n== brute force: every subset of ticks, no track moves more than one level ==")
local function legal(lv)
  if lv[1] ~= 0 then return false end
  for i=2,#lv do if lv[i] < 0 or lv[i] > lv[i-1]+1 then return false end end
  return true
end
local shapes = { {0,0,0,0,0}, {0,1,1,0,0}, {0,1,2,2,1,0}, {0,1,2,3,0,1}, {0,0,1,1,2,0} }
for _, shape in ipairs(shapes) do
  local n = #shape
  local okAll, badCase = true, nil
  for mask = 1, (1 << n) - 1 do
    local ticks = {}
    for i = 1, n do if (mask >> (i-1)) & 1 == 1 then ticks[#ticks+1] = i end end
    for _, opname in ipairs({"demoteMany","promoteMany"}) do
      local lv = {table.unpack(shape)}
      H[opname](lv, ticks)
      for i = 1, n do
        if math.abs(lv[i] - shape[i]) > 1 then okAll = false; badCase = opname.." "..show(ticks).." -> "..show(lv) end
      end
      if not legal(lv) then okAll = false; badCase = badCase or (opname.." "..show(ticks).." illegal "..show(lv)) end
    end
  end
  ck(okAll, "shape "..show(shape)..": every tick subset moves each track <= 1 level and stays legal"..(badCase and ("  ["..badCase.."]") or ""))
end

print("\n== moveLevels: move a whole folder up / down, planned on levels ==")
-- 1 holds 2,3 ; 4 root
local mv = {0,1,1,0}
local plan, dest = H.moveLevels(mv, 3, -1)
ck(plan and eq(plan,{0,1,1,0}) and dest == 1, "up: swap with sibling above -> same shape, insert before track 2 (dest 1)")
plan, dest = H.moveLevels(mv, 2, -1)
ck(plan and eq(plan,{0,0,1,0}) and dest == 0, "up from first child: hops out above the parent as its sibling: got "..show(plan or {}))
plan, dest = H.moveLevels(mv, 3, 1)
ck(plan and eq(plan,{0,1,0,0}) and dest == 4, "down from last child: leaves the folder, lands after track 4: got "..show(plan or {}))
plan, dest = H.moveLevels(mv, 2, 1)
ck(plan and eq(plan,{0,1,1,0}) and dest == 3, "down: swap with sibling below -> same shape, dest 3")
plan, dest = H.moveLevels(mv, 1, -1)
ck(plan == nil, "first track cannot move up: "..tostring(dest))
plan, dest = H.moveLevels(mv, 4, 1)
ck(plan == nil, "last track cannot move down: "..tostring(dest))
plan, dest = H.moveLevels(mv, 1, 1)
ck(plan and eq(plan,{0,0,1,1}) and dest == 4, "whole folder down past a root track: children come along: got "..show(plan or {}))

print("\n== the -2 closer case: moving a subtree whose last track closes an OUTER folder ==")
-- 1 > 2 > {3,4} ; 5 root.  depths [1,1,0,-2,0]: track 4 closes TWO folders.
-- Move folder 2 (2,3,4) down past 5.  Carrying depths would make 5 a child of 1.
local c2 = {0,1,2,2,0}
plan, dest = H.moveLevels(c2, 2, 1)
ck(plan and eq(plan,{0,0,0,1,1}), "folder 2 lands after 5 at root, its children intact: got "..show(plan or {}))
local dc = depthsFrom(plan or {}); local sc = 0; for i=1,#dc do sc = sc + dc[i] end
ck(sc == 0 and eq(levelsFrom(dc), plan or {}), "planned levels round-trip to well-formed depths "..show(dc))
ck(plan and plan[2] == 0, "track 5 (now 2nd) stayed at root - the parent did not swallow it")

print(("\n=== %d passed, %d failed ==="):format(pass,fail))
os.exit(fail==0 and 0 or 1)
