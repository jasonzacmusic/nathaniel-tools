-- @description NPH Flush Paste
-- @version 1.0.0
-- @author Jason Zac
-- @link https://daw.nathanielschool.com
-- @donation https://daw.nathanielschool.com/donate
-- @about Clear, paste, strip envelopes and save silently. Never opens Save As.
-- @changelog
--   1.0.0 - first public release. Crash-hardened (GUID identity + ValidatePtr2),
--           signature-based change detection, shared safety library.

-- NPH: Flush Paste
-- Replaces "Custom: Flush Paste".  Two bugs in the old chain:
--
--   1. Step 5 was 40022 "File: Save project AS..." -- a modal dialog on every
--      single press.  40026 is the silent save.
--
--   2. Step 6 is 41052.  Measured, not assumed:
--        41052 = "Item edit: ENABLE relative grid snap"   (a setter, idempotent)
--        41053 = disable,  41054 = toggle
--      It reports no toggle state -- GetToggleCommandState(41052) and
--      GetToggleCommandStateEx(0,41052) both return -1 -- and the state is not
--      in the project's GRID line either, because it is global, not per project.
--      Any guard of the form "if GetToggleCommandState(41052) ~= 1" is therefore
--      always true.  That is harmless here only because 41052 sets rather than
--      toggles; had anyone "fixed" it to 41054 it would have flipped on every
--      press.  The real state is readable through SWS as the config var
--      "relsnap", so we check that and leave 41052 alone when it is already on.
local r = reaper

r.Undo_BeginBlock2(0)
r.PreventUIRefresh(1)

r.Main_OnCommand(r.NamedCommandLookup("_SWS_DELALLITEMS"), 0)  -- clear selected tracks
r.Main_OnCommand(42398, 0)                                     -- paste items/tracks
r.Main_OnCommand(r.NamedCommandLookup("_S&M_REMOVE_ALLENVS"), 0)
r.Main_OnCommand(40297, 0)                                     -- unselect all tracks

r.PreventUIRefresh(-1)
r.Undo_EndBlock2(0, "NPH: Flush paste", -1)

-- Save silently -- but ONLY if this project has a file on disk.  40026 on a
-- never-saved project opens the Save-As dialog, which is the exact modal this
-- script exists to avoid.  On an unsaved project we skip the save and say so,
-- rather than ambushing you with a file browser mid-paste.
local _, projPath = r.EnumProjects(-1, "")
if projPath and projPath ~= "" then
  r.Main_OnCommand(40026, 0)                                   -- File: Save project
else
  r.ShowMessageBox(
    "Pasted and cleaned up.\n\nThis project has never been saved, so it was NOT saved automatically " ..
    "(that would have opened a Save As dialog).\n\nSave it once with Cmd+S and Flush Paste will save " ..
    "silently from then on.",
    "NPH Flush Paste", 0)
end

-- relative grid snap ON -- set, never toggle
if r.SNM_GetIntConfigVar then
  if r.SNM_GetIntConfigVar("relsnap", 0) ~= 1 then r.Main_OnCommand(41052, 0) end
end

r.UpdateArrange()
