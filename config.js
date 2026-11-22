// Steve & Chlo: connection to the app's database (Supabase project "Steve and Chlo").
// Both values are meant to be public. The tables allow no direct access at all:
// every read and write goes through database functions that check the shared code,
// and the code lives (hashed) in Supabase, never in this repo.
window.SC_CONFIG = {
  supabaseUrl: "https://hlmxrxqddorntteyqowu.supabase.co",
  supabaseKey: "sb_publishable_5RWyiLiVkVbA6buHPtBtfg_hdV5JxxN",
  // Public half of the push (VAPID) key. The private half is an Edge Function secret in Supabase.
  vapidKey: "BEGp_sIcP8EspxWqhc20_5wkWRJCxnfTdZkkkEXi_dGaz04l9LgXf7JhMdoWgCuBJ4QyxlRxyQ5xB3WxAQWIiRc"
};
