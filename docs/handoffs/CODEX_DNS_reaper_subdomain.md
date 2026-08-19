# Codex handoff — point reaper.nathanielschool.com at the Nathaniel Tools site

**Why:** the Nathaniel Tools site (user guide, app pages) is on the Vercel project `nph-daw`.
`daw.nathanielschool.com` is taken by DAW Mentor, so the suite gets `reaper.nathanielschool.com`.
The domain is already attached to the Vercel project (done 19-Aug-2026, `vercel domains add`).
Only the DNS record at name.com is missing — that needs Jason's name.com login.

**Do exactly this (name.com):**
1. Log in to name.com → My Domains → nathanielschool.com → DNS Records.
2. Add a record: **Type A · Host `reaper` · Answer `76.76.21.21` · TTL 300**.
   (Alternative accepted by Vercel: **CNAME · Host `reaper` · Answer `cname.vercel-dns.com`**.)
3. Save. Wait 2–5 minutes.
4. Verify: `curl -sI https://reaper.nathanielschool.com/guide | head -1` must say `HTTP/2 200`
   and `vercel domains inspect reaper.nathanielschool.com` (from `~/Documents/nph-reaper-suite/site`)
   must no longer print "not configured properly".
5. Then in the repo replace every `https://nph-daw.vercel.app` in `site/*.html`, `site/apps/*.html`,
   `site/sitemap.xml`, `site/robots.txt` and `README.md` with `https://reaper.nathanielschool.com`,
   commit, push, and `vercel deploy --prod --yes` from `site/`.

Never publish the `*.vercel.app` address anywhere public.
