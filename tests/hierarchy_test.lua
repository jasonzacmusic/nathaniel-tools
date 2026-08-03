-- Load the real module with a fake `reaper` so the pure maths can be tested.
reaper = { CountTracks=function() return 0 end, GetTrack=function() return nil end,
           GetMediaTrackInfo_Value=function() return 0 end, SetMediaTrackInfo_Value=function() end,
           GetSetMediaTrackInfo_String=function() return true,"" end,
           ReorderSelectedTracks=function() end, TrackList_AdjustWindows=function() end }
package.path = "/Users/nphmacmini/Documents/REAPER Media/NPH/lib/?.lua;" .. package.path
local H = require("nph_hierarchy")

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

print(("\n=== %d passed, %d failed ==="):format(pass,fail))
os.exit(fail==0 and 0 or 1)
