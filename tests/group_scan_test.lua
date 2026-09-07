-- Usage: lua tests/group_scan_test.lua (from repository root).
-- Verify the real scanner against generated track/group truth, including high
-- bit 32, high bank 64, failed API queries, stable order, and bounded API work.
local file = assert(io.open('apps/Group Deck.lua'))
local source = file:read('*a'); file:close()
local block = source:match('(local BEH = .-)\nlocal function firstFreeGroup')
assert(block)
local behavior = {VOLUME='vol',PAN='pan',MUTE='mute',SOLO='solo',RECARM='arm',MEDIA_EDIT='edit',RAZOR_EDIT='edit'}
local function run(n, high)
  local data, expected, calls = {}, {}, 0
  math.randomseed(721 + n)
  local max = high and 64 or 32
  for i=1,n do
    data[i] = {lo={}, hi={}, id='track-'..i}
    for name,key in pairs(behavior) do
      for _,suffix in ipairs({'_LEAD','_FOLLOW'}) do
        for bank=1,(high and 2 or 1) do
          local mask=0
          for bit=0,31 do
            if math.random(1,70)==1 then
              mask=mask | (1 << bit)
              local g=bit+1+(bank-1)*32
              expected[g]=expected[g] or {tracks={},flags={}}
              expected[g].tracks[i]=true;expected[g].flags[key]=true
            end
          end
          data[i][bank==1 and 'lo' or 'hi'][name..suffix]=mask
        end
      end
    end
  end
  local api={CountTracks=function()return n end,GetTrack=function(_,i)return data[i+1] end,
    GetTrackGUID=function(t)return t.id end,GetSetProjectInfo_String=function(_,key)return true,key end}
  local function read(t,name,bank)
    calls=calls+1
    -- Unsupported RAZOR_EDIT is an API error; remove from reference below.
    if name:find('RAZOR_EDIT') then error('unsupported') end
    return t[bank][name]
  end
  api.GetSetTrackGroupMembership=function(t,name,mask,value)assert(mask==0 and value==0);return read(t,name,'lo')end
  if high then api.GetSetTrackGroupMembershipHigh=function(t,name,mask,value)assert(mask==0 and value==0);return read(t,name,'hi')end end
  -- Build the independent truth from each recorded mask, excluding unsupported calls.
  expected={}
  for i,t in ipairs(data) do for bank=1,(high and 2 or 1) do for name,mask in pairs(t[bank==1 and 'lo' or 'hi']) do
    if not name:find('RAZOR_EDIT') then
      local key=behavior[name:gsub('_LEAD$',''):gsub('_FOLLOW$','')]
      for bit=0,31 do if mask & (1 << bit)~=0 then local g=bit+1+(bank-1)*32
        expected[g]=expected[g] or {tracks={},flags={}};expected[g].tracks[i]=true;expected[g].flags[key]=true
      end end
    end
  end end end
  local scan=assert(load('local r=reaper\n'..block..'\nreturn scan','scanner','t',setmetatable({reaper=api},{__index=_G})))()
  local start=os.clock();local result=scan();local elapsed=os.clock()-start
  local pos=1
  for g=1,max do if expected[g] then
    local actual=assert(result[pos]);assert(actual.n==g);pos=pos+1
    assert(actual.name=='TRACK_GROUP_NAME:'..g)
    local member=1
    for i=1,n do if expected[g].tracks[i] then assert(actual.members[member]=='track-'..i);member=member+1 end end
    assert(#actual.members==member-1)
    for _,key in pairs(behavior)do assert(actual.flags[key]==(expected[g].flags[key] or false))end
  end end
  assert(#result==pos-1)
  assert(calls==n*14*(high and 2 or 1),'query budget exceeded: '..calls)
  print(('PASS tracks=%d groups=%d queries=%d scanner=%.4fs'):format(n,max,calls,elapsed))
end
run(0,true);run(3,false);run(100,true);run(510,true)
