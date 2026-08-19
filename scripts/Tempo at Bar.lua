-- @description Tempo at Bar
-- @version 1.1.0
-- @author Jason Zac
-- @link https://github.com/jasonzacmusic/nathaniel-tools
-- @donation https://github.com/jasonzacmusic/nathaniel-tools
-- @about Insert or edit a tempo / time-signature marker exactly on a bar line, with a small dialog.
-- @changelog
--   1.1.0 - honest changelog.
--   1.0.0 - first public release.

-- Tempo / time-signature marker at the nearest BAR
-- Replaces "Custom: Tempo Nathaniel Tools" (40256 = insert at the raw, unquantized edit cursor).
--
-- Uses the MEASURE-based form of SetTempoTimeSigMarker, so the marker lands exactly
-- on a bar line with no float drift and stays put when later tempos change.
--
-- Two bugs found in testing and fixed here:
--   1. TimeMap_GetDividedBpmAtTime kept reporting the PROJECT-START tempo no matter
--      where you asked, so the dialog prefilled the wrong BPM as soon as the project
--      had more than one tempo marker.  Tempo now comes from TimeMap_GetMeasureInfo
--      (6th return), cross-checked against TimeMap_GetTimeSigAtTime.
--   2. The "very tough to lock" symptom.  Measured in REAPER 7.77: ptidx = -1 does
--      NOT stack when the new marker lands on the EXACT position of an existing one
--      -- it replaces it cleanly.  The old chain's problem was 40256, which inserts
--      at the raw, unquantized edit cursor, so every press landed a few milliseconds
--      away from the last one and the tempo map silently accumulated near-duplicates
--      that all looked like they were on the same bar.  Quantizing to the bar line
--      removes the cause.  We still locate the existing marker and edit it in place,
--      so the dialog can say "editing" and prefill the tempo that is really there.
--
-- Input accepts:  "120"   or   "120 4/4"   or   "4/4"   (tempo unchanged)
local r = reaper

local pos = (r.GetPlayState() & 1 == 1) and r.GetPlayPosition() or r.GetCursorPosition()

local function measureTime(m)
  local _, qn = r.TimeMap_GetMeasureInfo(0, m)
  return r.TimeMap2_QNToTime(0, qn)
end

local _, measures = r.TimeMap2_timeToBeats(0, pos)
local t0, t1 = measureTime(measures), measureTime(measures + 1)
local bar = (math.abs(pos - t0) <= math.abs(t1 - pos)) and measures or (measures + 1)
local barTime = measureTime(bar)

-- ---------------------------------------------------------------- current state
local _, _, _, num, den, curBpm = r.TimeMap_GetMeasureInfo(0, bar)
if not curBpm or curBpm <= 0 then
  local n2, d2, t2 = r.TimeMap_GetTimeSigAtTime(0, barTime)
  num, den, curBpm = n2 or num, d2 or den, t2
end
if not curBpm or curBpm <= 0 then curBpm = r.Master_GetTempo() end
if not num or num == 0 then num, den = 4, 4 end

-- Is there already a tempo/time-sig marker sitting on this bar?
--
-- Trap found in testing: GetTempoTimeSigMarker returns beatpos = 1e-11, NOT 0,
-- for a marker that sits exactly on a bar line -- so `bpos == 0` never matches
-- and the old scan found nothing, ever.  Match on TIME with a millisecond
-- tolerance, which is what actually identifies "the marker on this bar".
local existing = -1
for i = 0, r.CountTempoTimeSigMarkers(0) - 1 do
  local ok, tpos, mpos, bpos = r.GetTempoTimeSigMarker(0, i)
  if ok then
    local onBar = (mpos == bar and math.abs(bpos or 0) < 1e-6)
                  or (tpos and math.abs(tpos - barTime) < 1e-3)
    if onBar then existing = i break end
  end
end

-- ---------------------------------------------------------------- ask
local title = ("Nathaniel Tools Tempo  (bar %d%s)"):format(bar + 1, existing >= 0 and ", editing" or "")
local ok, input = r.GetUserInputs(title, 1, "BPM  [num/den] :,extrawidth=90",
                                  ("%g %d/%d"):format(curBpm, num, den))
if not ok then return end

local bpm  = tonumber(input:match("^%s*([%d%.]+)"))
local n, d = input:match("(%d+)%s*/%s*(%d+)")
n, d = tonumber(n), tonumber(d)
if not bpm then bpm = curBpm end
if not n or not d or n < 1 or d < 1 then n, d = num, den end
if bpm <= 0 or bpm > 960 then
  r.MB("BPM must be between 1 and 960.", "Nathaniel Tools Tempo", 0)
  return
end

-- ---------------------------------------------------------------- apply
r.Undo_BeginBlock2(0)
local done
if existing >= 0 then
  -- edit in place: keep it measure-based so it stays welded to the bar line
  done = r.SetTempoTimeSigMarker(0, existing, -1, bar, 0, bpm, n, d, false)
  if not done then   -- a time-based marker (e.g. the project's first) -- edit by time
    done = r.SetTempoTimeSigMarker(0, existing, barTime, -1, -1, bpm, n, d, false)
  end
else
  done = r.SetTempoTimeSigMarker(0, -1, -1, bar, 0, bpm, n, d, false)
end
r.Undo_EndBlock2(0, ("%s %g bpm %d/%d at bar %d")
  :format(existing >= 0 and "Set" or "Insert", bpm, n, d, bar + 1), -1)

if not done then
  r.MB("REAPER refused the tempo marker at bar " .. (bar + 1) .. ".", "Nathaniel Tools Tempo", 0)
end

r.UpdateTimeline()
r.UpdateArrange()
