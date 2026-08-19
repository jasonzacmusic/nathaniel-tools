-- @description StageRig Panic (footswitch)
-- @version 1.0.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about
--   Tells the running StageRig window to PANIC: mute and flush every patch
--   except the one you are playing. Bind it to a second pedal. Does nothing if
--   StageRig is not open.
-- @changelog
--   1.0.0 - first version.

reaper.SetExtState("NT_STAGERIG", "cmd", "panic", false)
