# Working the phone

A simulated iPhone runs on a Mac in GitHub's cloud. From this PC you send it steps ("tap this", "type that") and
get back a picture of its screen, a numbered list of what is on it, and a warning if the app hung or crashed.
Nothing is installed here and nothing on this PC is reachable from outside. All commands start with
`python scripts/ui-rig/rig.py`, written below as `rig`. Needs Python 3 and a signed-in `gh` (both are set up).

**Public repo:** everything you type and every picture passes through GitHub. Use only made-up names, `...@example.com`
emails and the rig's own sample videos. Never real accounts, passwords, or anyone's recordings.

## Start and stop

```
rig start mia --device small --photos short,4min     a phone called mia; prints READY with its size
rig -s mia do "launch fresh"                         the app, as if just installed
rig -s mia look                                      picture and list of the screen
rig stop mia                                         always, when you are done
```

Choose a name nobody else uses. `--device`: `small` (375x812), `se` (375x667), `normal`, `large`, `iphonex`.
`--ios`: `27` (newest), `26`, `18`, `16` (the oldest the app supports). `--app BRANCH` tests a branch (default `main`).
`--theme dark`, `--minutes 120` (it stops by itself then, and after 20 idle minutes: `--idle`), `--cloud off`.
Starting takes 5 to 10 minutes, or longer when all five Mac runners are taken; leave it and run `rig status mia` later
(`--no-wait`). `rig list` shows every session, `rig stop --all` stops yours. With one session open, `-s` is not needed.

## Steps

One per command (`rig -s mia tap "My videos"`) or several in one go, which is much faster than one by one:

```
rig -s mia do "tap Settings" "swipe up" "tap 'Storage'" "wait 2"
```

| | |
| --- | --- |
| What to touch | a name `"Edit video"`, a number from the last list `@12`, a point `120,300`, a kind `Button:Save`, the second of several `"Delete#2"` |
| Fingers | `tap T`, `doubletap T`, `press T 1.5` (long press), `drag FROM TO [seconds]`, `drag FROM by 60,-20`, `swipe up\|down\|left\|right [on T] [short\|long]`, `scrollto "Label"`, `pinch T 2.0` (0.5 closes), `rotate T 45` |
| Keyboard | `type "text"` (tap the field first), `key return\|delete`, `clear [how many]` |
| Getting around | `back` (swipe from the left edge), `home`, `reopen`, `background 30` (leave and return), `switcher`, `tray`, `orient landscape\|portrait`, `open https://...`, `open photos\|safari\|settings\|files` |
| The app | `launch` (close and open), `launch fresh` (delete, reinstall, forget permissions), `kill`, `launch sample` (made-up full library, nothing saved), `launch screen ID` (one prepared screen) |
| The phone | `theme dark\|light`, `textsize s\|l\|xxxl\|ax1..ax5`, `contrast on\|off`, `allow\|deny\|ask photos\|microphone\|speech\|all`, `photo short 4min` (adds samples to Photos; `photo` lists them), `clipboard` |
| Waiting | `wait 3`, `waitfor "Saved" 60`, `gone "Exporting" 300`, `settle` (until nothing moves) |
| Looking | `look`, `zoom x,y,w,h` (close-up), `full` (full resolution), `tree all`, `video start` ... `video stop` |
| Trouble | `hangcheck` (is it stuck, and doing what), `perf 10` (CPU, memory), `log 100 [word]`, `crashes`, `hangs` |
| Server | `net online\|offline\|slow\|error`, `plan free\|pro`. Sign-in: any email, code **123456** |

Samples: `short` 12 s, `landscape` 20 s, `square`, `silent` (no sound), `turned` (stored sideways), `hevc60`, `picture`,
`4min`, `9min`, `30min`, `big` (over 1 GB; the last two take a minute or two to arrive). Each shows a running clock.

## Reading the answer

```
1. ok: tap Settings  -> tapped Button "Settings" at 341,74
screen: C:\...\snapreel-rig\mia\007-shot.jpg  (375x812 points; 1 pixel = 1 point)
state: CPU 4%; memory 212 MB; the app answered in 0.4 s  [Snapreel; 5.1 s there and back]
on screen:
  @3 Button "Appearance" at 187,220 size 343x52 value="Match iPhone"
```

Open the picture each time (the Read tool shows it); its pixels are the numbers for `tap x,y`. A step waits up to
4 s for a name to appear, and the picture is taken when the screen stops moving. `*** HANG` means the app's main
thread was busy and did not answer for 8 s; `*** CRASH` comes with the crash. After a hang, try `home`, `reopen`,
and then `launch`. `[the screen did not change]` (with `do --each`) hints at a dead control. System questions
("Allow Photos?") are answered with `tap "Allow"`.
Pictures, a `history.txt` of every step, crash and hang files stay in `%TEMP%\snapreel-rig\NAME`.

Several phones on one runner: `rig start a:small b:se` (slower each; iOS 18 or older is best for that).
Without a person: `rig batch steps.txt --device small --photos 4min` runs a file of steps (one per line, `#` comments)
and downloads a picture per step, a video, the log, crashes, hangs and a report.
A browser instead of a phone: `rig start wes --web phone` or `--web desktop` (see [TESTER-WEB.md](TESTER-WEB.md)).

If something fails, the message says what to do; `rig status NAME` tells if the phone still lives. Exit codes: 0 all
steps done, 1 the rig could not, 2 a step failed.

For whoever runs the testers: `rig build --app BRANCH` once before starting them (sessions then skip the 8-minute build;
builds are kept 30 days and reused for any commit with the same app source), `rig media` once every 90 days (sample
videos), `rig clean` afterwards (removes what ended sessions left on GitHub). Limits and design: the hand-over note.
