# Steve & Chlo — notes for Claude

This repo **is the live home app** for Steve and Chlo (GitHub Pages, `main` branch, root). Built like `fore-the-v`: one page, Supabase behind it, installable to the home screen.

## How it's built
- `index.html` holds the whole app (HTML, CSS, JS). Pages are `section[data-view]`, routed by `#hash`: `today`, `calendar`, `meals`, `shop`, `recipes`, `todo`, `us`. Bottom tab bar has five tabs; `shop` and `recipes` are sub-tabs of Meals (`.sub` links at the top of both views).
- `config.js` holds the public Supabase URL and publishable key. Supabase project id `hlmxrxqddorntteyqowu` ("Steve and Chlo", separate from the golf project).
- Data: one table `sc_items (kind, id, data jsonb)`. Kinds: `meals`, `plan` (ids mon..fri), `ticks`, `extras`, `todos`, `chores`, `ideas`, `notes`, `counts`, `events` ({t, date, time, who, rep: ''|week|month|year}). RLS is on with no policies; the page only calls the functions `sc_status`, `sc_setup`, `sc_check`, `sc_all`, `sc_put`, `sc_patch`, `sc_del` (plain `fetch` to `/rest/v1/rpc/…`, no supabase-js). Every function checks the shared code (bcrypt hash in `sc_secret`). No Supabase auth, no realtime: the page polls `sc_all` every 8 s and on focus, with optimistic local updates and a serial write queue.
- Shared code: chosen in the app on first open (`sc_setup`, works once), remembered per phone in localStorage (`sc-code`). Never put the code in this repo or in chat. Changing it is a one-line SQL update (bottom of `supabase/setup.sql`).
- Calendar (15 Nov): events live in the app, no Google sync. `occurs()` handles repeats; Today shows today's and tomorrow's events. A new kind must also be added to the `sc_items_kind_check` constraint.
- Recipe book (21 Nov): `#recipes` lists every meal with search; `#recipes/<meal id>` is cook mode. Steps live on the meal as `steps:[{t, m}]` (`m` = minutes, gives a timer button). Steps can be typed in the app (one per line, "5 min" in a line makes a timer). Timers are per phone (localStorage `sc-timers`), keep running across screens (floating bar above the tabs), beep + vibrate when done, and cook mode asks the screen to stay awake. Type `Treat` meals are left out of "Suggest 5".
- Library index (21 Nov): the meal library (This week) and the Recipes list both have a search box (name, type, note, ingredients) and A–Z letter headers, with a letter bar (`.az`, shared `azRender()`) that sticks to the top while scrolling; the magnifier button jumps back to the search box.
- ml after grams (21 Nov): ingredient lists (library + cook mode) and recipe step text show "250 g (450 ml)" for things measured by volume. Densities live in `DENS` next to `qty()`; `ingLine()` for lists, `addMl()` for step text. Meat, veg, pasta and cheese blocks get no ml. Shopping list stays in grams. Add a `DENS` entry when a new jug/spoon ingredient appears.
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
- Ideas for V2: Google Calendar link, budget, edit-a-meal, edit-an-event, push reminders.
