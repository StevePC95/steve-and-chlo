# Steve & Chlo — notes for Claude

This repo **is the live home app** for Steve and Chlo (GitHub Pages, `main` branch, root). Built like `fore-the-v`: one page, Supabase behind it, installable to the home screen.

## How it's built
- `index.html` holds the whole app (HTML, CSS, JS). Pages are `section[data-view]`, routed by `#hash`: `today`, `meals`, `shop`, `todo`, `us`. Bottom tab bar.
- `config.js` holds the public Supabase URL and publishable key. Supabase project id `hlmxrxqddorntteyqowu` ("Steve and Chlo", separate from the golf project).
- Data: one table `sc_items (kind, id, data jsonb)`. Kinds: `meals`, `plan` (ids mon..fri), `ticks`, `extras`, `todos`, `chores`, `ideas`, `notes`, `counts`. RLS is on with no policies; the page only calls the functions `sc_status`, `sc_setup`, `sc_check`, `sc_all`, `sc_put`, `sc_patch`, `sc_del` (plain `fetch` to `/rest/v1/rpc/…`, no supabase-js). Every function checks the shared code (bcrypt hash in `sc_secret`). No Supabase auth, no realtime: the page polls `sc_all` every 8 s and on focus, with optimistic local updates and a serial write queue.
- Shared code: chosen in the app on first open (`sc_setup`, works once), remembered per phone in localStorage (`sc-code`). Never put the code in this repo or in chat. Changing it is a one-line SQL update (bottom of `supabase/setup.sql`).
- "Who am I" (Steve/Chlo) is per phone, localStorage `sc-me`.
- Schema lives in `supabase/setup.sql`; starter content in `supabase/seed.sql`. Keep both in step with the database. Supabase's SQL tools ask Steve for a confirmation; if it goes unanswered, hand him the script to paste into the SQL Editor.
- Claude can add meals, to-dos and so on for them with an `insert into sc_items` (or by editing in the app).
- Push to `main` and the site updates in about a minute.

## Design rules
- Tokens in `:root` only; every colour must work in light and dark.
- Blue speckled-enamel masthead, Steve = cobalt (`--steve`), Chlo = tomato (`--chlo`), fridge notes = butter yellow in Caveat handwriting. Fonts: Bricolage Grotesque (headings), Figtree (body), Caveat (notes and the ampersand only).
- New sections follow the pattern: `.head` (h2 + eyebrow), then `.card`s. Reuse `.list`, `.ck`, `.pill`, `.seg`, `.btn`, `armBtn` (tap twice to delete).
- Must work at 360px wide with no sideways scroll. They both have ADD: keep every screen short, one obvious action, no setup chores.

## Open items
- Icons in `icons/` are placeholders until Steve sends the real image.
- Ideas for V2: Google Calendar pull, budget, edit-a-meal, push reminders.
