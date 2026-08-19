# Codex handoff — update Waves so REAPER stops crashing (needs Jason's Waves login)

**Verified cause (19-Aug-2026, studio Mac mini):** REAPER crashed 5 times in 2 days
(18-Aug 19:31, 22:06; 19-Aug 09:29, 14:42, 20:57). Every `~/Library/Logs/DiagnosticReports/REAPER-*.ips`
has the SAME faulting thread: `std::mutex::lock` throwing inside
`InnerProcessDictionary2` (`wvWavesV15_4_4::WCInnerProcessListKeeper`) called from `WaveShell1-VST3`.
That is the Waves shared module `/Library/Application Support/Waves/Modules/InnerProcessDictionary2.bundle`
(version **2.4.0.1, dated 6 Jan 2025**). Nothing else appears in the stacks. Rain.RPP loads Waves via
`WaveShell1-VST3 16.0` (CLA-3A ×24, MannyM Reverb ×2, CLA Effects ×1). Installed: Waves Central 17.0.4,
WaveShells V15 (15.2/15.5/15.10) and V16 (16.0), Plug-Ins V15 (141) and V16 (140).

**Do exactly this:**
1. Waves Central is already open on the Mac, showing "please log in in your browser". Log in with
   Jason's Waves account in the browser tab it opened (or press Log in again).
2. In Waves Central: **Install Products → Update Available** (or "My Products" → filter Updates).
   Update EVERY listed item — especially anything called *Waves Central components*, *WaveShells*,
   *V16 / V15 plugins*. If it offers "Update all", use it. Let it finish; approve the macOS
   installer prompts if asked (they need the Mac password — Jason's).
3. Verify after: 
   ```
   defaults read "/Library/Application Support/Waves/Modules/InnerProcessDictionary2.bundle/Contents/Info" CFBundleShortVersionString
   ls -la "/Library/Application Support/Waves/Modules/"
   ls "/Applications/Waves/WaveShells V16/"
   ```
   The module version must be newer than 2.4.0.1 / dated 2026, and a shell newer than 16.0 should exist.
4. Relaunch REAPER, open `~/Documents/REAPER Media/Diya Shayda EP/Rain/Rain.RPP`, play 30 s, quit
   cleanly. Then check no new `REAPER-*.ips` appeared in `~/Library/Logs/DiagnosticReports/`.
5. Report: what was updated (versions before/after) and whether REAPER quit without a crash.

If Waves Central shows NO updates for the shell/module, the fallback is Waves' own guidance for this
exact crash ("mutex lock failed" in InnerProcessDictionary2 on macOS): in Waves Central →
Settings → *Repair / Reinstall* the installed V16 products, which rewrites the Modules folder.
