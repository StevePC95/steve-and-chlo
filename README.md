# Steve & Chlo

Our home app: tonight's dinner, the week's meals, a shopping list that builds itself, shared to-dos, house jobs, notes on the fridge, a date jar and countdowns.

- Open the link on your phone, then **Share → Add to Home Screen** for an app icon.
- The first time, enter the shared code. The phone remembers it.
- Tap **Steve** or **Chlo** at the top once so the app knows whose phone it is.

## What's in here

| File | What it is |
|---|---|
| `index.html` | The whole app |
| `config.js` | Public Supabase URL and key |
| `manifest.webmanifest`, `icons/` | Makes it installable |
| `supabase/setup.sql` | Creates the database table and functions |
| `supabase/seed.sql` | Starter meals, house jobs and date ideas |

## Notes

- The repo is public, so the code can be seen by anyone who finds it. Your data cannot: it sits in Supabase behind the shared code, and the code is not in this repo.
- Updating: edit, commit, push to `main`. GitHub Pages redeploys in about a minute.
