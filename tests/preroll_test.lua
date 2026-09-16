-- Usage: lua tests/preroll_test.lua; offline persistence and project-switch regression.
local projects,global={A={},B={}},{}
local active,current,dirty,writes='A',2,0,0
reaper={
 GetResourcePath=function()return "/tmp/nt-click-test" end,
 EnumProjects=function()return active end,
 SNM_GetDoubleConfigVar=function()return current end,
 SNM_SetDoubleConfigVar=function(_,v)current=v;writes=writes+1 end,
 GetProjExtState=function(p,_,k)return projects[p][k] and 1 or 0,projects[p][k] or '' end,
 SetProjExtState=function(p,_,k,v)projects[p][k]=v end,
 MarkProjectDirty=function()dirty=dirty+1 end,
 GetExtState=function(_,k)return global[k] or '' end,
 SetExtState=function(_,k,v,persist)assert(persist);global[k]=v end,
}
local function loadClick()return dofile('scripts/lib/nt_click.lua')end
local click=loadClick()
assert(click.prerollBars()==2)
assert(click.setPrerollBars(.5));assert(current==.5 and projects.A.preroll_bars=='0.5')
assert(global.preroll_bars=='0.5')
for i=1,50 do click.syncPreroll() end
assert(dirty==1 and writes==1,'idle frames must not dirty projects or rewrite native settings')
assert(not click.setPrerollBars(0));assert(not click.setPrerollBars(0/0));assert(not click.setPrerollBars(65));assert(current==.5)
active='B';assert(click.prerollBars()==.5,'new project inherits remembered default')
click.setPrerollBars(.25);active='A';assert(click.prerollBars()==.5,'A must restore its own fraction')
active='B';assert(click.prerollBars()==.25,'B must restore its own fraction')
current=4;click.syncPreroll();assert(projects.B.preroll_bars=='4','native dialog edits must be respected')
-- Emulate native preference resetting after closing REAPER and reopening saved A.
current=2;active='A';click=loadClick();assert(click.prerollBars()==.5,'saved project wins over global/native')
projects.C={};active='C';assert(click.prerollBars()==4,'new project uses last deliberately edited default')
print('PASS: 0.5/0.25 persist, distinct projects, restart restoration, native edits, valid input, no idle writes')
