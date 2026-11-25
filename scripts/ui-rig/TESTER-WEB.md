# Tester brief: the website

You are a normal person with a phone or a computer and nothing else. Somebody sent you a **Snapreel** link, or
you heard about the app and looked it up. Snapreel is an iPhone app that records your screen, camera or voice and
shares the recording as a link; this is its website. You don't know how it is built, and you must not find out:
**don't open any source file, plan, commit or other document in this project** except this one and
[README.md](README.md).

Your browser is headless Chrome in the cloud, worked with the same commands as the phone. Start it with

```
python scripts/ui-rig/rig.py start NAME --web phone         (375x812, touch)
python scripts/ui-rig/rig.py start NAME --web desktop       (1440x900, mouse)
```

It opens a private copy of the whole site with its own database: the accounts, videos and comments are made up, and
nothing you do reaches anyone. `open pricing` opens a page of this copy; `open https://snapreel.video/` opens the real
site, where you may **look only**: never send a form, a comment, a report, a sign-in or an email there.
Never use another browser or open a window on the owner's PC.

| Page | How to get there |
| --- | --- |
| Home, pricing, help, support, privacy, terms | `open home`, or `open pricing`, `open help`, `open support`, `open privacy`, `open terms` (but mostly by the links on the page) |
| Sign in | `open login`. `pro@example.com` is a Pro customer with videos, `free@example.com` a Free one; any other `...@example.com` is new. The code comes by email: `mail` shows the newest emails |
| Dashboard | after signing in, or `open app` |
| Watch pages | `links` lists them: wide, tall, voice, locked (password `snapreel`), with a button, expired, failed, still uploading, stopped; and `open v/nothing` |
| The player inside another page | the same address with `/embed` at the end |

`home` goes to the first page, `back` is the browser's Back, `swipe up` scrolls down, `key tab` moves the focus,
`log` shows what the browser complained about, `theme dark` asks for Dark, `launch fresh` forgets every cookie,
`orient landscape` turns the phone.

## How to work

1. **As a person first.** Without exploring, do these and note each moment you hesitated: understand from the
   first page what Snapreel is, what it costs and how to get it; watch a video somebody sent you, find a
   sentence in it, leave a comment with your name at a moment, react; open a locked one; sign in, find out who
   watched your video (`pro@example.com`), change its title, put a password on it, stop sharing it; find out how to delete your account;
   find out how to get help.
2. **Every link, button and field** on every page in the table, on a map you write down (page, then everything on it).
   Follow each link once, also in the footer and in the help articles. Try the keyboard on desktop: Tab through the
   page (can you see where you are?), Enter, Space, Escape, the arrow keys in the player.
3. **Be awkward.** Empty and wrong values; 1,000 letters; emoji; `<b>hi</b>` as a name; double clicks; Back in the
   middle; reload in the middle; signed out in another page; a wrong password three times; comment, then delete it;
   turn the phone; Dark; both sizes; a page opened by its address without signing in.
4. **Look at every picture.** The state line says when a page is **wider than the screen**: that is always a fault.
   Also: cut-off or overlapping text, empty boxes where a picture or video should be, moving things that jump,
   text over a picture that cannot be read, the wrong plan or price, different prices in two places, links that go
   nowhere, things that look pressable and are not (and the other way round), text that is hard to read.
5. **Watching**: does the video really play (two pictures 3 s apart differ, the time moves), pause, jump, change
   speed, go full screen, show captions, follow the transcript, remember the sound, start again at the end?

Faults, severities and the report are the same as in [TESTER.md](TESTER.md) ("What counts as a fault" and "The
report"). Say for each finding whether it is on phone, desktop or both, and whether the real site
(https://snapreel.video/) shows it too when it is a page you may look at there.

**Not testable here**: how emails look when they arrive, Sign in with Apple, payments, uploading from the app, visitors' countries, speed for real visitors.

## Areas

| # | Area | Sizes |
| --- | --- | --- |
| W1 | Home, pricing, help and its articles, support, privacy, terms, header, footer, a page that does not exist | phone and desktop |
| W2 | Watch pages (all of `links`), comments, reactions, transcript, report, share, the embedded player | phone and desktop |
| W3 | Sign-in, dashboard, one video's page, its settings, insights and comments, account, signing out; once as Free and once as Pro | desktop, then phone |
