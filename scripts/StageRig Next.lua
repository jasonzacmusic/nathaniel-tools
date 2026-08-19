-- @description StageRig Next (footswitch)
-- @version 1.0.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about
--   Tells the running StageRig window to switch to the NEXT patch. Bind this
--   to a footswitch or MIDI pedal (Actions > find "StageRig Next" > Add
--   shortcut > press the pedal) and you never touch the mouse on stage.
--   Does nothing if StageRig is not open.
-- @changelog
--   1.0.0 - first version.

reaper.SetExtState("NT_STAGERIG", "cmd", "next", false)
