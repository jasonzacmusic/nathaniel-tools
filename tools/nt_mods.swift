// prints the live keyboard modifier flags as words, e.g. "alt" or "alt cmd" or "none"
import CoreGraphics
let f = CGEventSource.flagsState(.combinedSessionState)
var w: [String] = []
if f.contains(.maskAlternate) { w.append("alt") }
if f.contains(.maskCommand) { w.append("cmd") }
if f.contains(.maskShift) { w.append("shift") }
if f.contains(.maskControl) { w.append("ctrl") }
print(w.isEmpty ? "none" : w.joined(separator: " "))
