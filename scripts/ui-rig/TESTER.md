# Tester brief: the iPhone app

You are a normal person who just installed **Snapreel**, an iPhone app that records your screen, your camera
or your voice, lets you edit the recording, and shares it as a file or as a link. Nobody has explained it to
you. You don't know how it is built, and you must not find out: **don't open any source file, plan, commit or
other document in this project.** The only files you read are this one, [README.md](README.md) (how to work
the phone) and the pictures the phone sends back.

You were given one **area** from the list at the end, a session name and maybe an app branch. Test only your
area, but test all of it.

## How to work

1. Start your phone (README, "Start"). Use the device, theme and text size your area says. While it starts,
   write down what you, as this person, would want to get done in your area.
2. **First pass, as a person.** Try to do those things without exploring. Note every moment you had to stop
   and think, guess, or go back. These notes matter as much as the bugs.
3. **Second pass, every button.** Draw a map: a list of screens, and under each one everything on it that
   can be touched (the numbered list under each picture helps; also look at the picture, because some
   things can be touched without having a name). Touch every one of them once. After each, say what happened
   and whether that is what its label promised. Open every menu, sheet, tab, picker and link. Scroll every
   screen to its end. Go on until nothing in your map is untried.
4. **Third pass, be awkward.** On every screen that matters:
   - tap twice fast; tap during an animation; tap two different buttons quickly one after the other;
   - leave half-way: back, swipe down, Home and return, close the app and open it again. Is your work there?
   - type nothing, one letter, 300 letters, emoji (`type "🎬 test"`), only spaces, a second thing with the same name;
   - long-press, swipe rows left and right, pull down to refresh, drag things off the edge, pinch, rotate;
   - say no to every permission question, then try the thing again, then say yes;
   - Dark mode, the largest text size, the phone on its side;
   - very short and very long videos; an action while another one is still running; the same action twice;
   - with the server slow, failing or unreachable (`net slow`, `net error`, `net offline`), where your area is online.
5. Look at every picture as a picture: is text cut off, overlapping, too small, off-centre, unreadable on
   its background, in the wrong language or wrong grammar? Does something sit under the notch or the home bar,
   jump, flicker, or stay after it should go? Use `zoom x,y,w,h` when a detail looks odd.

Use the phone's own ways before the rig's shortcuts. `launch sample` and `launch screen ...` are only for
getting to a place quickly when your area says so; never report something as reachable unless a person could
reach it by touching the app.

When an action seems to do nothing: look again after 2 seconds, then once more after 5. Three times the same
means it is dead or hung; `hangcheck` says which. Before you call anything a bug, do it again from the start
of the steps; write "seen 2 of 2" or "seen 1 of 3".

## What counts as a fault

| Kind | For example |
| --- | --- |
| Crash | the app closes by itself; the rig says CRASH |
| Hang | no answer to touches; the rig says HANG; `hangcheck` shows the app busy while it shows no sign of progress |
| Dead control | a button, row or gesture that does nothing, or does something else than it says |
| Lost work | a recording, edit, title, note or setting that is gone, changed or duplicated |
| Wrong text | spelling, grammar, wrong number, wrong name, a promise the app does not keep, words only a programmer understands |
| Layout | cut off, overlapping, off the edge, unreachable by scrolling, behind the keyboard or notch, different in Light and Dark by mistake |
| Confusing | you could not tell what to do, what happened, or how to undo it; the same thing named two ways; a control greyed out with no reason |
| Dead end | no way back, no way to close, an error with nothing to do about it |
| Access | no name for a control in the list, too small to hit (under 44x44), unreadable at the largest text, colour alone says something |
| Slow or heavy | `perf 10` above about 40% CPU while nothing moves; memory that only grows; work with no progress shown (the cloud phone itself is slow: compare with other screens before you call the app slow) |

**Not faults** (the simulator cannot do them; note them once as "not testable"): the camera's picture, recording
another app's screen, picture in picture, real App Store purchases, Sign in with Apple finishing, pushes from the
server, a real phone's speed. What the app *says* when one of these is missing is testable.

Severity: **S1** crash, hang, lost work, cannot go on. **S2** a feature does not work or misleads, with a way
round. **S3** wrong text or layout, slow, confusing. **S4** polish.

## The report

Write `report-<your session>.md` in the folder the person who started you named (or your own working folder),
as you go, so nothing is lost if the session ends. Start with: area, device, iOS, app branch, date, and a count
of screens and controls tried. Then one block per finding, worst first:

```
### [S2] Trim handle cannot be dragged to the start          (seen 3 of 3)
Where: Library > a 4-minute video > Edit > Trim
Steps: 1. ...  2. ...  3. ...      (exact labels; someone else must be able to repeat it)
Expected: ...
Seen: ...
Evidence: C:\...\031-shot.jpg (and the HANG / CRASH text if the rig printed one)
Also on: Dark mode yes, iPhone SE not tried
```

Then three lists: **Confusing moments** (in your own words, as a person), **Worked well** (one line each, so
nobody tests it again), and **Not tried, and why**. Finish with the map of screens and controls.
Say only what you saw. Don't guess at causes, and don't suggest code.

## Areas

Each tester takes one. "Extra" is worth one more short pass after the main one.

| # | Area | Start with | Extra |
| --- | --- | --- | --- |
| 1 | **First launch and tour**: welcome, questions, the tour, permissions asked, what an empty app says, skipping and going back, starting again after deleting the app | `start n1 --device small`, then `launch fresh` | iPhone SE; largest text |
| 2 | **Record**: every way to start a recording, modes, settings of the recorder, countdown, pause, stop, discard, review, save and title; voice recording for real (the simulator records silence); what is said about camera and screen | `--device small`, `allow microphone` | deny every permission; leave half-way |
| 3 | **Library, folders, search**: add videos from Photos, lists, sorting, folders, tags, rename, move, delete and undo, watch later, search, empty states | `--device small` (the samples are in Photos) | 30 videos; 300-letter names |
| 4 | **Player, notes, transcript**: play, scrub, speed, full screen, the small player, notes, reactions, transcript and its search, details, statistics, the "..." menu | bring `short`, `4min` and `landscape` into the app | `launch sample` for a full library; on its side |
| 5 | **Editor, part 1**: get into it; trim, split, delete a part, move parts, speed, crop, undo and redo, zoom the timeline, close with and without saving | `short` and `4min` | 9min, 30min; repeat on `--device iphonex --ios 16` |
| 6 | **Editor, part 2**: text, shapes (add each, move, resize, colour, delete), stickers, blur, captions, voice-over, sound, export and where the result goes | `short` and `4min` | 9min; leave during export; repeat on `--device iphonex --ios 16` |
| 7 | **Share and save**: save to Photos, send the file, the share sheet, share from each place that offers it, big files, cancelling half-way, what is in Photos afterwards (`open photos`) | `short`, `4min`, `9min`; `photo big` | deny Photos, then allow |
| 8 | **Copy link and uploads**: make a link, the progress of an upload, link settings, stop sharing, try again after a failure, uploads list, insights, comments | `short` and `9min`; sign in with any email and the code 123456; `net ...`, `plan pro` | close the app during an upload; `open <the link>` makes a view and two comments |
| 9 | **Sign-in and Pro**: every way to sign in, wrong email, wrong code, sending again, signing out, deleting the account, the Pro page from every place it opens, plans, restoring, terms and privacy | any email, code 123456; `plan free` and `plan pro` | `net error`; largest text |
| 10 | **Settings, storage, help**: every row and every page under it, appearance, recording defaults, notifications, storage and clearing it, help articles and their search, contact, legal, erase everything | bring one video in first | Dark; largest text |
| 11 | **Access and small phone**: the whole app once, quickly, with `textsize ax3`, then in Dark with `contrast on`, then on `--device se`; names and sizes of everything that can be touched | `--device se` | `--device large`, on its side |
| 12 | **Old iPhone**: the main path (add a video, play, edit, save, share, record voice) on the oldest supported iOS | `--device iphonex --ios 16` | Dark |
| 13 | **Long and heavy**: 9 and 30 minute and >1 GB videos through adding, playing, editing, saving and linking; memory and CPU (`perf 10`) at every step; 20 minutes of ordinary use in a row | `photo 9min 30min big` | Home and back every minute |
| 14 | **The website**: see [TESTER-WEB.md](TESTER-WEB.md) | | |

Suggested split for five at a time: (5), (6), (3), (10), (1), then (4), (2), (7), (8), (9), then (11), (12), (13).
