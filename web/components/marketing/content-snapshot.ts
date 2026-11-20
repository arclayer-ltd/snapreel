// Written by scripts/web-sync-content.mjs. Don't edit by hand; edit the sources and re-run it:
//   Snapreel/Features/Help/help-articles.json, docs/legal/privacy-policy.md, docs/legal/terms-of-use.md
import type { HelpData } from "./content-types";

export const helpSnapshot: HelpData = {
  "categories": [
    {
      "id": "start",
      "title": "Getting started",
      "systemImage": "sparkles"
    },
    {
      "id": "recording",
      "title": "Recording",
      "systemImage": "video.fill"
    },
    {
      "id": "screen",
      "title": "Screen recording",
      "systemImage": "rectangle.inset.filled.on.rectangle"
    },
    {
      "id": "library",
      "title": "Your library",
      "systemImage": "folder.fill"
    },
    {
      "id": "watching",
      "title": "Watching",
      "systemImage": "play.rectangle.fill"
    },
    {
      "id": "notes",
      "title": "Notes and reactions",
      "systemImage": "text.bubble.fill"
    },
    {
      "id": "sharing",
      "title": "Sharing and saving",
      "systemImage": "square.and.arrow.up.fill"
    },
    {
      "id": "links",
      "title": "Share links and Pro",
      "systemImage": "link"
    },
    {
      "id": "privacy",
      "title": "Privacy and storage",
      "systemImage": "lock.fill"
    },
    {
      "id": "trouble",
      "title": "Troubleshooting",
      "systemImage": "wrench.and.screwdriver.fill"
    }
  ],
  "articles": [
    {
      "id": "what-is-snapreel",
      "category": "start",
      "title": "What Snapreel is for",
      "summary": "Record your screen, camera or voice and send the video to anyone.",
      "body": [
        {
          "type": "paragraph",
          "text": "Snapreel turns a quick recording into something you can send. Show a bug instead of describing it, talk someone through a document, or leave a message in your own voice."
        },
        {
          "type": "heading",
          "text": "What you can record"
        },
        {
          "type": "bullets",
          "items": [
            "**Screen** – everything on your iPhone's screen, with your voice if you like.",
            "**Camera** – you, or whatever is in front of you, with the front or back camera.",
            "**Audio** – just your voice, with a live waveform while you talk."
          ]
        },
        {
          "type": "heading",
          "text": "No account needed"
        },
        {
          "type": "paragraph",
          "text": "Recording, your library, transcripts and sending files all work without an account, and your recordings are kept on this iPhone. You only sign in when you want to share a recording as a link that plays in any browser."
        }
      ],
      "related": [
        "first-recording",
        "share-links",
        "privacy"
      ]
    },
    {
      "id": "first-recording",
      "category": "start",
      "title": "Make your first recording",
      "summary": "From the red button to a video you can send, in five steps.",
      "useCases": [
        "work",
        "personal"
      ],
      "body": [
        {
          "type": "steps",
          "items": [
            "Tap the red **Record** button in the middle of the tab bar.",
            "Choose **Camera**, **Screen** or **Audio** at the bottom of the recorder.",
            "Tap the big record button. A short countdown gives you a moment to get ready.",
            "Tap stop when you're done. Your recording plays back so you can check it.",
            "Give it a title, then tap **Share** to send it or **Done** to keep it in your library."
          ]
        },
        {
          "type": "tip",
          "text": "Changed your mind? **Delete** on the review screen removes the recording before it goes anywhere."
        }
      ],
      "related": [
        "camera-recording",
        "screen-start",
        "share"
      ]
    },
    {
      "id": "find-your-way",
      "category": "start",
      "title": "Find your way around",
      "summary": "What each tab does, and where Settings lives.",
      "body": [
        {
          "type": "bullets",
          "items": [
            "**Home** – your newest recordings, Watch later and what you watched recently.",
            "**Library** – every recording, plus your folders.",
            "**Record** – the red button opens the recorder.",
            "**Notifications** – what Snapreel has done for you, such as saving a recording or finishing a transcript.",
            "**Search** – find recordings by title, folder, tag or the words said in them."
          ]
        },
        {
          "type": "paragraph",
          "text": "The gear at the top of each tab opens Settings, with recording defaults, notifications, storage and this help centre."
        },
        {
          "type": "tip",
          "text": "Want the quick tour again? Go to **Settings › Take the tour again**."
        }
      ],
      "related": [
        "what-is-snapreel",
        "watch-later-history"
      ]
    },
    {
      "id": "camera-recording",
      "category": "recording",
      "title": "Record with the camera",
      "summary": "Flip cameras, pause, start over and keep your notes in view.",
      "useCases": [
        "education"
      ],
      "body": [
        {
          "type": "paragraph",
          "text": "Open the recorder and choose **Camera**. You'll see yourself in the viewfinder before anything is recorded."
        },
        {
          "type": "bullets",
          "items": [
            "**Flip** – the button at the bottom right swaps between the front and back camera.",
            "**Countdown** – recording starts after a short countdown. Change its length, or turn it off, in recording settings.",
            "**Pause** – pause and carry on as often as you like. It all ends up in one video.",
            "**Restart** – throws the take away and begins a fresh one, after checking with you first."
          ]
        },
        {
          "type": "paragraph",
          "text": "When you stop, you'll see the recording before it's added to your library."
        }
      ],
      "related": [
        "recording-settings",
        "speaker-notes",
        "audio-recording"
      ]
    },
    {
      "id": "audio-recording",
      "category": "recording",
      "title": "Record just your voice",
      "summary": "Audio recordings for when a picture isn't needed.",
      "useCases": [
        "personal"
      ],
      "body": [
        {
          "type": "paragraph",
          "text": "Choose **Audio** in the recorder to record sound only. A waveform moves with your voice, so you can see the microphone is hearing you."
        },
        {
          "type": "paragraph",
          "text": "You can pause and carry on, just like a camera recording. Audio recordings sit in your library alongside your videos and play with their own artwork."
        },
        {
          "type": "tip",
          "text": "The Photos app only holds photos and videos, so audio recordings can't be saved there. Use **Share** to send them instead."
        }
      ],
      "related": [
        "share",
        "transcripts"
      ]
    },
    {
      "id": "recording-settings",
      "category": "recording",
      "title": "Change quality, countdown and microphone",
      "summary": "Choose how new recordings are made.",
      "body": [
        {
          "type": "paragraph",
          "text": "Tap the gear in the recorder, or go to **Settings › Recording**. Both change the same settings."
        },
        {
          "type": "bullets",
          "items": [
            "**Quality** – 720p makes the smallest files (about 40 MB a minute), 1080p looks sharp on any screen (about 90 MB a minute) and 4K is for the back camera when you want every detail (about 300 MB a minute).",
            "**Microphone** – whether new recordings start with the microphone on.",
            "**Countdown** – off, or 3, 5 or 10 seconds before recording starts.",
            "**Camera** – which camera the recorder opens with, and whether the front camera is mirrored."
          ]
        }
      ],
      "related": [
        "camera-recording",
        "storage"
      ]
    },
    {
      "id": "speaker-notes",
      "category": "recording",
      "title": "Keep notes in view while you record",
      "summary": "Speaker notes sit over the camera but never appear in the video.",
      "body": [
        {
          "type": "steps",
          "items": [
            "In the recorder, tap the pencil button at the top.",
            "Type or paste what you want to say.",
            "Turn on the option to show your notes while recording."
          ]
        },
        {
          "type": "paragraph",
          "text": "Your notes scroll over the viewfinder while you record, so you can glance at them without losing your place. They're only on your screen: the recording itself doesn't include them."
        }
      ],
      "related": [
        "camera-recording"
      ]
    },
    {
      "id": "import-video",
      "category": "recording",
      "title": "Bring in a video from Photos",
      "summary": "Add a video you already have to your library.",
      "body": [
        {
          "type": "steps",
          "items": [
            "Open the recorder and tap **Import** at the bottom left.",
            "Choose a video.",
            "Snapreel copies it into your library and lets you know when it's done."
          ]
        },
        {
          "type": "paragraph",
          "text": "Because you pick the video yourself, Snapreel doesn't need access to the rest of your photo library. The original stays in Photos, and the copy in Snapreel can be titled, sorted, transcribed and shared like any recording."
        }
      ],
      "related": [
        "folders",
        "transcripts"
      ]
    },
    {
      "id": "screen-start",
      "category": "screen",
      "title": "Start a screen recording",
      "summary": "Record anything on your screen, in any app.",
      "useCases": [
        "work",
        "education"
      ],
      "body": [
        {
          "type": "paragraph",
          "text": "Screen recordings use the recording feature built into iOS, so they keep going when you leave Snapreel."
        },
        {
          "type": "steps",
          "items": [
            "Open the recorder and choose **Screen**.",
            "Tap the record button. A list of apps that can record appears.",
            "Choose **Snapreel**, and turn on the microphone if you'd like your voice included.",
            "Tap **Start Broadcast**. After a three-second countdown, everything on your screen is recorded.",
            "Go to the app you want to show."
          ]
        },
        {
          "type": "tip",
          "text": "Notifications that arrive while you record are recorded too. Turn on a Focus such as Do Not Disturb first if you'd rather they didn't appear."
        }
      ],
      "related": [
        "screen-stop",
        "screen-what-records",
        "screen-wont-start"
      ]
    },
    {
      "id": "screen-stop",
      "category": "screen",
      "title": "Stop a screen recording and find it",
      "summary": "Two ways to stop, and where the recording goes.",
      "body": [
        {
          "type": "paragraph",
          "text": "While you record, a red indicator shows at the top of the screen. To stop:"
        },
        {
          "type": "bullets",
          "items": [
            "Tap the red indicator at the top of the screen, then tap **Stop**.",
            "Or come back to Snapreel and tap the stop button."
          ]
        },
        {
          "type": "paragraph",
          "text": "Snapreel then saves the recording to your library. If you're in another app, a notification lets you know it's ready. Tap it to give the recording a title and send it."
        },
        {
          "type": "tip",
          "text": "No notification? Just open Snapreel. Finished screen recordings are added to your library as soon as the app opens."
        }
      ],
      "related": [
        "screen-start",
        "rename",
        "no-notifications"
      ]
    },
    {
      "id": "screen-what-records",
      "category": "screen",
      "title": "What a screen recording includes",
      "summary": "Know what's captured before you send it.",
      "body": [
        {
          "type": "bullets",
          "items": [
            "Everything you see on the screen, including notifications and the keyboard as you type.",
            "Sound from the apps you use, and your voice if the microphone was on."
          ]
        },
        {
          "type": "paragraph",
          "text": "Some apps protect what they show, such as films from streaming services. Those parts appear black in the recording."
        },
        {
          "type": "paragraph",
          "text": "Watch the recording back before you send it. If something private slipped in, delete it and record again."
        }
      ],
      "related": [
        "screen-start",
        "mic-not-recorded"
      ]
    },
    {
      "id": "folders",
      "category": "library",
      "title": "Organise recordings into folders",
      "summary": "Create folders, move recordings and tidy up.",
      "body": [
        {
          "type": "steps",
          "items": [
            "Go to **Library** and choose **Folders**.",
            "Tap **New folder** and give it a name.",
            "To move a recording, tap **…** on it and choose **Move to folder**."
          ]
        },
        {
          "type": "paragraph",
          "text": "A recording lives in one folder at a time, or in none. Deleting a folder doesn't delete anything inside it: its recordings go back to **My videos**."
        }
      ],
      "related": [
        "tags-and-search",
        "rename"
      ]
    },
    {
      "id": "tags-and-search",
      "category": "library",
      "title": "Find anything with tags and search",
      "summary": "Tags group recordings across folders; search looks everywhere.",
      "body": [
        {
          "type": "paragraph",
          "text": "Tap **…** on a recording and choose **Tags** to add words like *bug*, *feedback* or *lessons*. A recording can have as many tags as you like."
        },
        {
          "type": "paragraph",
          "text": "The **Search** tab looks through titles, folder names, tags and the words spoken in your recordings. Tap a line that was said and the recording plays from that moment."
        },
        {
          "type": "tip",
          "text": "Spoken words can only be found once a recording has a transcript."
        }
      ],
      "related": [
        "transcripts",
        "folders"
      ]
    },
    {
      "id": "rename",
      "category": "library",
      "title": "Rename a recording",
      "summary": "Give recordings names you'll recognise later.",
      "body": [
        {
          "type": "paragraph",
          "text": "New recordings get a title with the date and time, such as *Screen recording – 18 Nov, 09:41*. To change it:"
        },
        {
          "type": "bullets",
          "items": [
            "Tap the title on the review screen straight after recording.",
            "In your library, tap **…** on the recording and choose **Rename**.",
            "While watching, open the recording's actions and choose **Edit title**."
          ]
        },
        {
          "type": "paragraph",
          "text": "If a recording still has its automatic title an hour later, Snapreel can send a gentle reminder. Turn it off in **Settings › Notifications** if you'd rather not."
        }
      ],
      "related": [
        "folders",
        "no-notifications"
      ]
    },
    {
      "id": "playback",
      "category": "watching",
      "title": "Playback controls",
      "summary": "Skip, change speed, go full screen or keep watching while you browse.",
      "body": [
        {
          "type": "bullets",
          "items": [
            "Tap the video to show or hide the controls.",
            "Skip back or forward 5 seconds with the arrows either side of play.",
            "Drag along the bar to jump to any moment.",
            "Tap the speed button to watch at anything from 1x to 2x. Snapreel remembers your choice.",
            "Use picture in picture to keep watching over other apps, or go full screen.",
            "Tap the chevron to shrink the player into a bar and keep watching while you look around."
          ]
        },
        {
          "type": "paragraph",
          "text": "Snapreel remembers where you stopped and picks up from there next time."
        }
      ],
      "related": [
        "watch-later-history",
        "notes"
      ]
    },
    {
      "id": "watch-later-history",
      "category": "watching",
      "title": "Watch later and history",
      "summary": "Save recordings for later and see what you've watched.",
      "body": [
        {
          "type": "paragraph",
          "text": "Tap **…** on any recording and choose **Watch later**. Your list is on **Home**."
        },
        {
          "type": "paragraph",
          "text": "**History** on Home lists what you've watched, most recent first, with a bar showing how far you got."
        },
        {
          "type": "paragraph",
          "text": "Swipe left on an entry to take it off either list. The recording itself stays in your library."
        }
      ],
      "related": [
        "playback",
        "find-your-way"
      ]
    },
    {
      "id": "transcripts",
      "category": "watching",
      "title": "Transcripts",
      "summary": "Read, search and jump around a recording by what was said.",
      "useCases": [
        "education"
      ],
      "body": [
        {
          "type": "paragraph",
          "text": "Snapreel can turn the speech in a recording into a transcript, using speech recognition on this iPhone. The audio never leaves your device."
        },
        {
          "type": "steps",
          "items": [
            "Open a recording and switch to **Transcript**.",
            "Tap **Make a transcript**. The first time, iOS asks whether Snapreel may use speech recognition.",
            "When it's ready, tap any line to jump to that moment."
          ]
        },
        {
          "type": "paragraph",
          "text": "If your iPhone can't recognise a language on the device, Snapreel tells you rather than sending audio anywhere. Recordings without speech won't have a transcript."
        },
        {
          "type": "paragraph",
          "text": "On iPhones with Apple Intelligence, a short summary of the transcript also appears in the recording's details."
        },
        {
          "type": "tip",
          "text": "Once you've allowed speech recognition, new recordings are transcribed automatically and you're told when each one is ready."
        }
      ],
      "related": [
        "tags-and-search",
        "permissions"
      ]
    },
    {
      "id": "notes",
      "category": "notes",
      "title": "Add notes at a moment",
      "summary": "Pin a thought to the exact second it matters.",
      "useCases": [
        "work",
        "education"
      ],
      "body": [
        {
          "type": "steps",
          "items": [
            "While watching, tap **Add note**. Playback pauses at that moment.",
            "Type your note and send it.",
            "It appears under **Notes** with its time, such as *Note at 0:14*."
          ]
        },
        {
          "type": "paragraph",
          "text": "Tap a note's time to jump straight there. To change or delete a note, swipe it or use its menu."
        },
        {
          "type": "paragraph",
          "text": "Notes are just for you. They stay with the recording on this iPhone and aren't part of the video file you send."
        }
      ],
      "related": [
        "reactions",
        "playback"
      ]
    },
    {
      "id": "reactions",
      "category": "notes",
      "title": "React with emoji",
      "summary": "Mark the best moments with a quick emoji.",
      "body": [
        {
          "type": "paragraph",
          "text": "Tap an emoji in the bar under the video. It's added at that moment and shows on the timeline, so you can spot the highlights at a glance."
        },
        {
          "type": "paragraph",
          "text": "The button at the end of the bar opens every emoji, with the ones you used recently at the top."
        },
        {
          "type": "paragraph",
          "text": "Like notes, reactions are yours alone and aren't included in the video file you send."
        }
      ],
      "related": [
        "notes"
      ]
    },
    {
      "id": "share",
      "category": "sharing",
      "title": "Send a recording",
      "summary": "Send the video file with AirDrop, Messages, Mail or any app.",
      "useCases": [
        "work",
        "personal"
      ],
      "body": [
        {
          "type": "steps",
          "items": [
            "Open the recording, or tap **…** on it in your library.",
            "Tap **Share**.",
            "Choose AirDrop, Messages, Mail or another app."
          ]
        },
        {
          "type": "paragraph",
          "text": "You're sending the video file itself, so whoever gets it can watch it without Snapreel."
        },
        {
          "type": "tip",
          "text": "Long recordings make big files. AirDrop is quickest for those, and some email services won't accept large attachments."
        }
      ],
      "related": [
        "save-to-photos",
        "storage",
        "share-links"
      ]
    },
    {
      "id": "save-to-photos",
      "category": "sharing",
      "title": "Save a recording to Photos",
      "summary": "Keep a copy in your Photos library.",
      "useCases": [
        "personal"
      ],
      "body": [
        {
          "type": "paragraph",
          "text": "Tap **Save to Photos** on the review screen or in a recording's actions. The first time, iOS asks whether Snapreel may add to your photos. Snapreel can only add: it can't see the rest of your library."
        },
        {
          "type": "paragraph",
          "text": "The copy in Photos is separate from the one in Snapreel, so deleting one leaves the other."
        },
        {
          "type": "tip",
          "text": "Audio recordings can't be saved to Photos. Use **Share** to send them to Files or another app."
        }
      ],
      "related": [
        "share",
        "permissions"
      ]
    },
    {
      "id": "privacy",
      "category": "privacy",
      "title": "Where your recordings are kept",
      "summary": "On this iPhone, plus snapreel.video for the recordings you share as links.",
      "body": [
        {
          "type": "paragraph",
          "text": "Recordings, titles, folders, tags, notes, reactions and transcripts are kept in Snapreel's own space on this iPhone, protected by iOS. Nothing is uploaded until you tap **Copy link**."
        },
        {
          "type": "bullets",
          "items": [
            "A recording you share as a link is uploaded to snapreel.video with its title and transcript, and stays there until you stop sharing it or delete your account.",
            "Snapreel shows no ads and collects no analytics about you. Viewers of your links are counted with an anonymous cookie on the watch page, never across other sites.",
            "Transcripts are made on the device.",
            "If you back up your iPhone to iCloud or a computer, Snapreel's data is part of that backup."
          ]
        },
        {
          "type": "paragraph",
          "text": "Deleting Snapreel deletes everything on this iPhone, but not your share links: stop sharing them, or delete your account, to remove them from snapreel.video."
        }
      ],
      "related": [
        "permissions",
        "storage",
        "delete-account"
      ]
    },
    {
      "id": "storage",
      "category": "privacy",
      "title": "Free up space",
      "summary": "See what Snapreel uses and clear out old recordings.",
      "body": [
        {
          "type": "paragraph",
          "text": "Go to **Settings › Storage** to see how much space your recordings use and how much is left on this iPhone. Your largest recordings are listed, so you can delete what you no longer need."
        },
        {
          "type": "paragraph",
          "text": "**Delete all my data** removes every recording, folder, note, reaction, transcript and notification from Snapreel in one go. Your settings stay. This can't be undone."
        },
        {
          "type": "tip",
          "text": "Lower quality makes smaller files: 720p uses less than half the space of 1080p."
        }
      ],
      "related": [
        "iphone-full",
        "recording-settings"
      ]
    },
    {
      "id": "permissions",
      "category": "privacy",
      "title": "Permissions Snapreel asks for",
      "summary": "What each permission is for, and how to change it.",
      "body": [
        {
          "type": "bullets",
          "items": [
            "**Camera** – for camera recordings.",
            "**Microphone** – for your voice in any recording.",
            "**Photos** – only to add recordings you choose to save.",
            "**Speech recognition** – for transcripts, made on this iPhone.",
            "**Notifications** – to tell you about your recordings."
          ]
        },
        {
          "type": "paragraph",
          "text": "Snapreel asks for each one only when you first need it. To change your mind, open the Settings app, scroll down to **Snapreel** and switch them on or off."
        }
      ],
      "related": [
        "privacy",
        "mic-not-recorded"
      ]
    },
    {
      "id": "screen-wont-start",
      "category": "trouble",
      "title": "Screen recording won't start",
      "summary": "What can stop a screen recording, and what to do.",
      "body": [
        {
          "type": "bullets",
          "items": [
            "**Screen Time** – if screen recording is restricted, open the Settings app and go to Screen Time › Content & Privacy Restrictions › Content Restrictions › Screen Recording, then choose Allow.",
            "**Mirroring or AirPlay** – stop showing your screen on a TV or Mac first.",
            "**CarPlay** – screen recording isn't available while CarPlay is connected.",
            "**A work or school iPhone** – your organisation may have turned screen recording off.",
            "**Not enough space** – free some up and try again."
          ]
        },
        {
          "type": "paragraph",
          "text": "If none of these apply, restart your iPhone and try once more."
        }
      ],
      "related": [
        "screen-start",
        "iphone-full"
      ]
    },
    {
      "id": "mic-not-recorded",
      "category": "trouble",
      "title": "My voice isn't in the recording",
      "summary": "Check the microphone before you start.",
      "body": [
        {
          "type": "bullets",
          "items": [
            "**Screen recordings** – in the list where you chose Snapreel, the microphone button must be on (red) before you tap Start Broadcast.",
            "**Permission** – open the Settings app, tap Snapreel and make sure Microphone is on.",
            "**Recording settings** – check the microphone setting behind the gear in the recorder.",
            "**Calls** – during a phone or video call, iOS may keep the microphone for the call."
          ]
        }
      ],
      "related": [
        "screen-start",
        "permissions"
      ]
    },
    {
      "id": "iphone-full",
      "category": "trouble",
      "title": "My iPhone is full",
      "summary": "What happens when space runs out, and how to make room.",
      "body": [
        {
          "type": "paragraph",
          "text": "Recordings need free space while they're being made. When your iPhone gets close to full, Snapreel warns you before you start and can notify you when space runs low."
        },
        {
          "type": "paragraph",
          "text": "If space runs out mid-recording, Snapreel stops and keeps as much as it can. A recording that couldn't be finished stays in your library with a note saying how much room it needs."
        },
        {
          "type": "steps",
          "items": [
            "In Snapreel, go to **Settings › Storage** and delete recordings you no longer need.",
            "In the Settings app, check General › iPhone Storage for other large apps and files.",
            "Go back to the recording and tap **Try again**."
          ]
        }
      ],
      "related": [
        "storage",
        "save-failed"
      ]
    },
    {
      "id": "save-failed",
      "category": "trouble",
      "title": "A recording couldn't be saved",
      "summary": "Try again, or find out what went wrong.",
      "body": [
        {
          "type": "paragraph",
          "text": "Occasionally a recording can't be finished, for example if your iPhone ran out of space while saving. It stays in your library, marked as not saved."
        },
        {
          "type": "bullets",
          "items": [
            "Tap **Try again**.",
            "If space is the problem, free some up first.",
            "Tap **Delete** if you don't need it."
          ]
        },
        {
          "type": "paragraph",
          "text": "Recordings still saving when Snapreel closes carry on the next time you open it."
        }
      ],
      "related": [
        "iphone-full",
        "storage"
      ]
    },
    {
      "id": "no-notifications",
      "category": "trouble",
      "title": "I'm not getting notifications",
      "summary": "Check Snapreel's settings and your iPhone's.",
      "body": [
        {
          "type": "steps",
          "items": [
            "In Snapreel, go to **Settings › Notifications** and switch on the kinds you want.",
            "If Snapreel says notifications are off for the app, use the button there to turn them on.",
            "Check whether a Focus, such as Do Not Disturb or Sleep, is silencing them."
          ]
        },
        {
          "type": "paragraph",
          "text": "Everything Snapreel tells you also appears in the **Notifications** tab, even when alerts are off."
        }
      ],
      "related": [
        "permissions",
        "screen-stop"
      ]
    },
    {
      "id": "share-links",
      "category": "links",
      "title": "Share a recording as a link",
      "summary": "Copy a link that plays in any browser, no app or account needed to watch.",
      "useCases": [
        "work",
        "school",
        "personal"
      ],
      "body": [
        {
          "type": "steps",
          "items": [
            "Open a recording, or finish one, and tap **Copy link** (the link button next to Share). It's also in a recording's actions in your Library.",
            "The first time, sign in with Apple or with a code sent to your email.",
            "The link is on your clipboard straight away. Paste it into Messages, Mail, Slack or anywhere else.",
            "Snapreel uploads the video in the background. Until it's done, the watch page says it's uploading; then it plays."
          ]
        },
        {
          "type": "paragraph",
          "text": "Uploads carry on when you leave Snapreel, and pick up where they stopped if you lose your connection. You can see them in **Settings › Account › Shared links**."
        },
        {
          "type": "tip",
          "text": "Pasted into Mail, the link shows a picture of the recording with a play button, so it looks like a video."
        },
        {
          "type": "heading",
          "text": "What viewers see"
        },
        {
          "type": "paragraph",
          "text": "Anyone with the link can watch in a browser, with your title, the transcript as captions, and a place to comment and react. Links aren't listed or searchable."
        }
      ],
      "related": [
        "link-settings",
        "link-insights",
        "snapreel-pro"
      ]
    },
    {
      "id": "link-settings",
      "category": "links",
      "title": "Passwords, expiry and comments",
      "summary": "Decide who can watch a link, for how long, and what they can do.",
      "body": [
        {
          "type": "paragraph",
          "text": "Open a shared recording, tap **…** then **Link settings**. You can also tap the link in **Settings › Account › Shared links**."
        },
        {
          "type": "bullets",
          "items": [
            "**Comments and reactions** – on or off, on every plan.",
            "**Password** – viewers type it once before watching. Snapreel Pro.",
            "**Expiry** – the link stops working after a day, a week or 30 days. Snapreel Pro.",
            "**Downloads** – let viewers save the video. Snapreel Pro.",
            "**Call to action** – a button under the video, such as “Book a call”. Snapreel Pro."
          ]
        },
        {
          "type": "heading",
          "text": "Stop sharing"
        },
        {
          "type": "paragraph",
          "text": "**Stop sharing** at the bottom of Link settings deletes the link, its video, views and comments from snapreel.video. The recording stays on this iPhone, and you can share it again later with a new link."
        }
      ],
      "related": [
        "share-links",
        "snapreel-pro"
      ]
    },
    {
      "id": "link-insights",
      "category": "links",
      "title": "See who watched, and their comments",
      "summary": "Views, viewers, comments and reactions on your links.",
      "body": [
        {
          "type": "paragraph",
          "text": "A shared recording says **Shared · 12 views** in your Library and in the player. Open it and tap **Stats** for its numbers, or the **Comments** tab for what viewers wrote."
        },
        {
          "type": "bullets",
          "items": [
            "A view counts once someone watches 5 seconds, three-quarters of the video, or the end. Your own views don't count.",
            "Unique viewers are counted by browser, with an anonymous cookie. Viewers who don't give a name show as Anonymous.",
            "With Snapreel Pro you also see each viewer, how far they got, a chart of where people stopped, and their countries."
          ]
        },
        {
          "type": "heading",
          "text": "Delete a comment or block a viewer"
        },
        {
          "type": "paragraph",
          "text": "Tap **…** on a comment. **Delete comment** removes it; **Delete and block** also stops that viewer commenting or reacting on any of your videos."
        },
        {
          "type": "tip",
          "text": "Viewers' reactions appear on the player's timeline in small rings, so you can tell them from your own."
        }
      ],
      "related": [
        "share-links",
        "link-settings"
      ]
    },
    {
      "id": "snapreel-pro",
      "category": "links",
      "title": "Snapreel Pro",
      "summary": "Unlimited links, longer videos and full insights. Everything else stays free.",
      "body": [
        {
          "type": "paragraph",
          "text": "Recording, your library, transcripts and sending files are free for everyone, for good. Snapreel Pro is only about share links."
        },
        {
          "type": "bullets",
          "items": [
            "**Free** – 25 links at a time, each up to 5 minutes, at 720p, with views, comments and reactions.",
            "**Pro** – unlimited links up to 2 hours at 1080p, who watched and how far, passwords, expiry, downloads, a call-to-action button, and no Snapreel badge."
          ]
        },
        {
          "type": "paragraph",
          "text": "Pro is $5.99 a month, or $39.99 a year with a free week first (prices vary by country). Subscribe in **Settings › Snapreel Pro**. It renews automatically until you cancel."
        },
        {
          "type": "heading",
          "text": "Cancel, restore or get a refund"
        },
        {
          "type": "steps",
          "items": [
            "To cancel, open the **Settings** app, tap your name, then **Subscriptions › Snapreel**. You keep Pro until the end of the period you've paid for.",
            "On a new iPhone, tap **Restore Purchases** on the Snapreel Pro screen.",
            "Apple handles payments, so refunds are requested from Apple at reportaproblem.apple.com."
          ]
        }
      ],
      "related": [
        "share-links",
        "delete-account"
      ]
    },
    {
      "id": "delete-account",
      "category": "links",
      "title": "Sign out or delete your account",
      "summary": "What happens to your links, and to your subscription.",
      "body": [
        {
          "type": "paragraph",
          "text": "Go to **Settings › Account**."
        },
        {
          "type": "bullets",
          "items": [
            "**Sign out** – your links keep working and your recordings stay on this iPhone. Sign in again to see their views and comments.",
            "**Delete account** – your share links stop working, and their videos, views, comments and reactions are deleted from snapreel.video, with your email address and sign-in. If you used Sign in with Apple, Snapreel's access to it is revoked."
          ]
        },
        {
          "type": "paragraph",
          "text": "Recordings on this iPhone are not touched. To remove them too, use **Settings › Storage › Delete all my data**."
        },
        {
          "type": "tip",
          "text": "Deleting your account doesn't cancel Snapreel Pro, because Apple bills it. Cancel it first in the Settings app › your name › Subscriptions."
        }
      ],
      "related": [
        "snapreel-pro",
        "privacy"
      ]
    },
    {
      "id": "upload-stopped",
      "category": "trouble",
      "title": "A link's upload stopped",
      "summary": "Why an upload pauses, and how to get it going again.",
      "body": [
        {
          "type": "paragraph",
          "text": "Uploads wait by themselves while you're offline and carry on when you're back. If one stops for good, Snapreel tells you and the recording shows **Upload stopped**."
        },
        {
          "type": "steps",
          "items": [
            "Open **Settings › Account › Shared links**.",
            "Tap **Try again** next to the upload.",
            "Keep Snapreel open for a moment on Wi-Fi if the video is long."
          ]
        },
        {
          "type": "bullets",
          "items": [
            "Free links take recordings up to 5 minutes; longer ones need Snapreel Pro.",
            "A link can hold up to 2 GB.",
            "If the recording was deleted from this iPhone before the upload finished, it can't be sent again."
          ]
        }
      ],
      "related": [
        "share-links",
        "snapreel-pro"
      ]
    }
  ]
};

export const privacySnapshot = "# Privacy policy\n\nLast updated: 20 November 2026\n\nThis policy explains how Snapreel, the iPhone app and the website at snapreel.video, handles your information. The short answer: your recordings stay on your iPhone, unless you choose to share one as a link.\n\n## Who we are\n\nSnapreel is made by Rezan Ferdous, an individual developer based in Bangladesh, not a company. \"We\", \"us\" and \"our\" in this policy mean Rezan Ferdous.\n\n- Address: Enayetpur, Sirajganj 6751, Bangladesh\n- Email: [support@snapreel.video](mailto:support@snapreel.video)\n\nUnder data protection laws such as the EU and UK General Data Protection Regulation (GDPR), we are the \"controller\" of the information described here. Write to the email address above about anything in this policy, in English or Bengali.\n\n## In short\n\n- You can record, organise, transcribe and send files without an account. All of that stays on your iPhone.\n- If you share a recording as a link, you need an account, and that recording is uploaded to snapreel.video until you stop sharing it.\n- We don't sell your information, show ads, or track you across other companies' apps and websites.\n- The people who watch your links are counted with a cookie that only snapreel.video uses.\n\n## What stays on your iPhone\n\nSnapreel keeps the following on your device, in storage that only Snapreel can reach, protected by iOS data protection:\n\n- your recordings and their thumbnails\n- titles, folders, tags, notes and emoji reactions\n- transcripts, and summaries where your iPhone can make them\n- the list in the Notifications tab\n- your settings and recent searches\n\nWe can't see any of it, and none of it is uploaded unless you share that recording as a link. If you back up your iPhone to iCloud or a computer, Apple's backup may include it, under Apple's own privacy policy.\n\n## Your account\n\nYou need an account only to share recordings as links or to subscribe to Snapreel Pro. You can sign in with Apple or with a code sent to your email address. We keep:\n\n- your email address (with Sign in with Apple you can choose to share a private relay address instead)\n- your name, if you give one or Apple shares it when you first sign in; it's shown on your watch pages\n- your account ID\n- for each device you're signed in on, when you signed in, its internet address and its browser or device type, to keep your account secure\n- your link settings, such as your colour and call-to-action button, and whether you want email alerts\n- your Snapreel Pro plan, its renewal date and Apple's transaction ID for it, if you subscribe\n- a push notification token for each iPhone you're signed in on, so we can tell you about new viewers and comments\n\nYour sign-in session is kept in your iPhone's Keychain, or in a cookie when you use the web dashboard at snapreel.video.\n\n## Recordings you share as links\n\nWhen you tap Copy link, Snapreel uploads that one recording to snapreel.video: a copy of the video made for the web, a still picture and a 3-second preview, with its title, length, size and, if one was made on your iPhone, its transcript (used for captions on the watch page).\n\nAnyone you send a link to can watch the recording, read its title and transcript, and see your name. Links aren't listed or searchable. A link with a password is shown only to people who type it.\n\n## People who watch your links\n\nWatching a link doesn't need an account. The watch page at snapreel.video sets a first-party cookie (`sr_vs`) that holds a random ID and lasts a year, so we can count views and unique viewers, keep a viewer's place, apply blocks and stop abuse. A link with a password sets a second cookie for 12 hours after you type the password. Neither is used for advertising, shared with anyone else, or read on other websites. The counts they give are statistics about each video, not a profile of you. You can block or delete these cookies in your browser and still watch; you'll just be counted as a new viewer each time, and a password link will ask for its password again. To stop your views being counted at all, turn on **Don't count my views** at the bottom of any watch page: it sets a small cookie (`sr_nocount`, for a year) and we then record no views from that browser, while `sr_vs` stays so that blocks and abuse limits still work.\n\nFor each view we record:\n\n- roughly where the viewer is: their country, worked out from their internet address, which we don't store\n- the kind of device (phone, tablet or computer) and the website they came from\n- how much of the video they watched, and when\n- a name, only if the viewer types one to comment or react, and their Snapreel account, if they're signed in\n\nThe link's owner sees view counts. With Snapreel Pro they also see each viewer's country, device and how far they watched, with the name the viewer typed or, for a viewer signed in to Snapreel, their account name.\n\nTo protect snapreel.video from spam and abuse, we also count requests per internet address. We store only a one-way code made from the address, never the address itself, and delete it within a day.\n\n## Comments, reactions, blocks and reports\n\nViewers can comment and react if the owner allows it. A comment's name and text are shown to the owner and to everyone who can watch the link. The owner can delete any comment and block the viewer who wrote it; a block is kept so that viewer can't comment or react on the owner's videos again.\n\nAnyone can report a video from its watch page. A report holds the reason, any details you write and, if you give it, your email address so we can reply. It's stored with the video and sent to our support mailbox.\n\n## Snapreel Pro and payments\n\nSnapreel Pro is an auto-renewing subscription sold by Apple through the App Store. Apple handles your payment details; we never see them. Apple tells us which plan you bought and when it renews, changes, is refunded or ends, and we store that against your account. Cancellations and refunds are handled by Apple.\n\n## Emails and notifications\n\nWe email you sign-in codes and, unless you turn them off, alerts when someone watches, comments on or reacts to your links. Every alert has a link to turn alerts off. We don't send marketing email. Push notifications about your links go through Apple's push service, and you can turn them off in the Settings app or in **Settings › Notifications** in Snapreel.\n\n## The Lock Screen card\n\nWhile you record your screen, Snapreel shows a card with the time on your Lock Screen. When a screen recording ends while Snapreel is in the background, Snapreel sends our server the card's push code (a random code Apple makes for that one card) and how long the recording ran, so Apple's push service can stop the card. The server passes them on and keeps nothing. Nothing about your recording is sent.\n\n## Permissions\n\nSnapreel asks for a permission only when a feature needs it. You can change your answer at any time in the Settings app.\n\n- **Camera** – to record camera videos.\n- **Microphone** – to record your voice with a recording.\n- **Photos (add only)** – to save recordings you choose to your Photos library. When you import a video, you pick it in Apple's photo picker, which gives Snapreel only that video.\n- **Speech recognition** – to make transcripts. Snapreel only uses recognition that runs on your iPhone; your audio is never sent anywhere to be transcribed.\n- **Notifications** – to tell you when a recording is saved, a transcript is ready, space is running low, or someone watched or commented on one of your links.\n\nScreen recording uses the broadcast feature built into iOS. You start and stop it yourself, and the recording is written straight into Snapreel's storage on your iPhone.\n\n## Why we use your information, and our legal bases\n\n- **To provide Snapreel to you** (performing our agreement with you, the terms of use): your account and sign-in, hosting and showing the recordings you share, comments and reactions, alerts, and Snapreel Pro. Without your email address we can't create an account; everything else in an account is optional.\n- **To count views and show link owners who watched, and to keep Snapreel safe** (our legitimate interests, and the owner's, in useful statistics and in a service free of spam and abuse): the viewer cookie, view records, rate limits, blocks, reports and security records. You can object to this; write to us.\n- **To follow the law** (legal obligation): for example keeping records we must keep, or answering a valid request from a court or authority.\n- **With your consent**: push notifications and the iPhone permissions above, which you can turn off at any time.\n\nWe don't use your information to make automated decisions about you, and we don't use your recordings to train AI models.\n\n## Who processes your information\n\nWe use these companies to run Snapreel. They act on our instructions, under data processing terms that let them use your information only to provide their service to us:\n\n- **Supabase** (Supabase Pte. Ltd., Singapore) – our database, sign-in and video storage, hosted on Amazon Web Services in the United States (us-east-1).\n- **Vercel** (Vercel Inc., United States) – hosts snapreel.video and its servers, in the United States, with a worldwide network that delivers pages.\n- **Resend** (United States) – sends our emails, such as sign-in codes and alerts, from the United States.\n- **Hostinger** (Hostinger International Ltd., Cyprus) – our domain's name servers and the support@snapreel.video mailbox.\n- **Apple** – Sign in with Apple, push notifications and App Store payments. For payments and its own services, Apple is responsible for your information under Apple's privacy policy.\n\nWe may also disclose information if the law requires it, to protect people from harm, or to deal with illegal content, for example by reporting child sexual abuse material to the authorities. If Snapreel is ever transferred to someone else, your information would go with it under this policy, and we'd tell you first.\n\n## International transfers\n\nWe run Snapreel from Bangladesh, and our providers store your information in the United States. If you're in the European Economic Area, the United Kingdom or Switzerland, your information is protected in transfer as follows: Vercel and Resend are certified under the EU-US Data Privacy Framework and its UK extension, and Supabase uses the European Commission's Standard Contractual Clauses, with the UK Addendum, in its data processing terms. Hostinger is a company in the EU. Write to us for a copy of the safeguards.\n\n## How long we keep it\n\n- **Your account, profile and plan**: until you delete your account. Deleting it removes them, your shared videos and their files at once.\n- **Sign-in records** (device, internet address): until you sign out on that device or delete your account.\n- **Push tokens**: until you sign out on that iPhone, delete your account, or Apple tells us the token no longer works.\n- **A shared recording and its views, comments and reactions**: while you share the link. When you stop sharing, they're deleted at once; we keep only the link's short code for 30 days, so the link says it was removed, and then delete that too.\n- **A link that expires**: it stops playing on its expiry date. Its recording and activity are kept for 30 days in case you extend it, then deleted in the same way.\n- **An upload that never finishes**: marked as failed after 48 hours, and its files are deleted 7 days later.\n- **Rate-limit records** (a one-way code made from an internet address): up to 1 day.\n- **The record of which alerts we've sent** (so you don't get the same one twice): 90 days.\n- **Reports**: until the reported link is deleted, plus its 30-day removal notice.\n- **Emails to support**: until your question is resolved, and then for up to a year.\n- **Logs kept by our hosting providers**, which can include internet addresses: up to 30 days.\n- **Viewer cookies**: up to a year in the viewer's browser (12 hours for a password cookie), or until the viewer clears them.\n\n## Security\n\nInformation travels to and from snapreel.video over encrypted connections (HTTPS), and our providers encrypt it where it's stored. Recordings are kept in private storage, and each link is served through short-lived signed addresses. Link passwords are stored only as secure hashes. Only the developer has administrative access. No service is perfectly secure; if a breach puts you at risk, we'll tell you and the authorities where the law requires.\n\n## Your choices and rights\n\n- Stop sharing any link in its **Link settings**. Its video, views and comments are deleted from snapreel.video.\n- Delete any comment on your videos, and block the viewer who wrote it.\n- Turn alerts about viewers and comments off in **Settings › Notifications**, or with the link in any alert email.\n- Delete your account in **Settings › Account › Delete account**, or on the web dashboard at snapreel.video. This deletes your links and everything on snapreel.video and your sign-in, and revokes Sign in with Apple. It doesn't cancel an App Store subscription: cancel that in the Settings app › your name › Subscriptions.\n- **Settings › Storage › Delete all my data** removes everything Snapreel keeps on your iPhone.\n\nDepending on where you live, you also have the right to ask us for a copy of your information (including in a portable format), to correct it, to delete it, to restrict or object to how we use it, and to withdraw consent at any time. Write to [support@snapreel.video](mailto:support@snapreel.video); we'll answer within a month and won't charge you. We may need to check that the request comes from you.\n\nIf you're unhappy with how we handle your information, write to the same address with \"Privacy complaint\" in the subject. We'll acknowledge it within 30 days and tell you what we did about it. You can also complain to a data protection authority at any time: in the EU, the authority in your country; in the UK, the Information Commissioner's Office (ico.org.uk); in Bangladesh, the authority under the Personal Data Protection Act 2026; elsewhere, the authority where you live.\n\n### If you live in the United States\n\nWe don't sell or share personal information for targeted advertising, and we don't use or disclose sensitive personal information except to provide Snapreel. You can use the rights above whatever state you live in, and we won't treat you differently for using them. If we turn down your request, you can appeal by replying to our answer; if you're still unhappy after the appeal, you can contact your state's attorney general. Snapreel doesn't track you across other websites, and no one else tracks you through it, so browser \"Do Not Track\" and Global Privacy Control signals don't change anything here.\n\n## Children\n\nYou must be at least 13 to create a Snapreel account, or older where the law where you live requires a higher age to use online services without a parent's consent (for example 14, 15 or 16 in some European countries). If you're under 18, a parent or guardian must agree to you having an account, as the law in Bangladesh and some other countries requires. Snapreel isn't directed at children under 13, and we don't knowingly collect information from them. If you think a child has given us information, write to us and we'll delete it.\n\n## Changes\n\nIf this policy changes, we'll update the date at the top, and tell you in the app or by email before a change that matters takes effect.\n\n## Contact\n\nRezan Ferdous, Enayetpur, Sirajganj 6751, Bangladesh. Email: [support@snapreel.video](mailto:support@snapreel.video)\n";

export const termsSnapshot = "# Terms of use\n\nLast updated: 20 November 2026\n\nThese terms are an agreement between you and Rezan Ferdous, an individual developer based in Bangladesh (\"we\", \"us\"), for your use of Snapreel: the iPhone app and the website at snapreel.video. By using Snapreel, creating an account or subscribing, you agree to them. If you don't agree, please don't use Snapreel. Our [privacy policy](https://snapreel.video/privacy) explains how we handle your information.\n\n- Address: Enayetpur, Sirajganj 6751, Bangladesh\n- Email: [support@snapreel.video](mailto:support@snapreel.video)\n\n## The short version\n\n- Recording, your library and sending files work on your iPhone without an account, free.\n- Share links need an account. Snapreel Pro, a paid subscription sold through the App Store, adds more.\n- What you record belongs to you, and so does the responsibility for it. Don't share anything illegal or harmful.\n- Snapreel is provided as it is, so keep copies of anything important.\n\n## Who can use Snapreel\n\nYou must be at least 13 to create an account, or older if the law where you live requires a higher age to use online services without a parent's consent. If you're under 18, or under the age of majority where you live, you need a parent's or guardian's permission to create an account or subscribe. If you use Snapreel for an organisation, you confirm you're allowed to accept these terms for it.\n\n## The app and Apple's licence agreement\n\nThe Snapreel app is licensed to you under Apple's [Licensed Application End User License Agreement](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/) (the \"Standard EULA\"), which lets you use the app on Apple devices you own or control, as the App Store's rules allow. These terms add to it for Snapreel's account, share links, Snapreel Pro and the website. Where the two conflict about the app's licence, the Standard EULA wins on that point. You may not copy, modify, reverse engineer, resell or redistribute the app, except where the law gives you that right.\n\n## Your account\n\nYou need an account to share recordings as links and to subscribe to Snapreel Pro. You can sign in with Apple or with a code sent to your email address. Keep access to your Apple Account and email account safe: anyone who can sign in as you can manage your links. Tell us at once if you think someone else has used your account.\n\nYou can delete your account at any time in **Settings › Account › Delete account**, or on the web dashboard at snapreel.video.\n\n## Your recordings and share links\n\nEverything you make with Snapreel is yours. Recordings stay on your device unless you send them somewhere or share them as a link.\n\nWhen you share a recording as a link, you give us a worldwide, non-exclusive, free licence to store it, make web copies, previews and captions of it, and show it to the people who open the link, only to run Snapreel and only for as long as you share it. This licence ends when you stop sharing the link or delete your account, apart from copies that take a short time to clear from our providers' systems.\n\nAnyone with a link can watch the recording and, if you allow them, comment, react and download it. You decide who gets your links, and you can stop sharing a link at any time. You're responsible for having the rights and permissions needed to share what you upload, including from the people who appear or can be heard in it.\n\n## Acceptable use\n\nYou're responsible for what you record and share, and for the comments you leave. Don't use Snapreel to record, share or post anything that:\n\n- breaks the law, or that you don't have the right to share, such as films, music, TV, games or someone else's work\n- records people without their permission where the law requires it, or shares someone's private information\n- is sexual content involving minors, or exploits or endangers children in any way\n- is sexual or intimate imagery of someone shared without their consent, or is sexually explicit\n- harasses, threatens, bullies or incites hatred or violence against anyone, or promotes terrorism\n- glorifies or encourages self-harm or suicide\n- impersonates someone, or misleads people about who you are\n- is spam, malware, phishing or a scam\n- tries to break, overload, scrape or get around the security or limits of snapreel.video\n\n## Comments and viewers\n\nPeople who watch your links can comment and react if you allow it. Their comments belong to them, and they're responsible for them. You can delete any comment on your videos and block the viewer who wrote it from all your videos. Viewers can report a video to us from its watch page.\n\n## How we moderate\n\nWe don't watch or scan shared recordings in advance. We act on reports from viewers and others, on what we notice ourselves, and on orders from courts and authorities. Every report is reviewed by a person, the developer, not by an automated system. To keep snapreel.video working, we also limit how often anyone can comment, react or report, and we filter obvious automated spam. Comments whose name or text contains words from a short list of slurs and abuse are held, unseen by viewers, until the link's owner approves or deletes them.\n\nIf content breaks these terms or the law, we may remove it, stop its link from playing, or suspend or close the account that shared it. We close the accounts of people who seriously or repeatedly break these terms, including repeat copyright infringers, and we report child sexual abuse material and threats to life or safety to the authorities.\n\n## Reporting content and takedowns\n\nIf you think a video or comment on snapreel.video breaks these terms or the law, use \"Report this video\" on its watch page, or write to [support@snapreel.video](mailto:support@snapreel.video). Please include the link, what's wrong and why, and, for a copyright or other legal complaint, your name and email address, the work or right concerned, and a statement that you believe in good faith that your report is accurate. We review reports promptly, and we'll tell you what we decided if you gave us your email address.\n\nsupport@snapreel.video is also our point of contact for authorities and courts, and our single point of contact for users and authorities under the EU Digital Services Act; please write in English or Bengali.\n\nIf we remove or restrict your content or account, we'll tell you what we did and why, unless the law stops us or it would put someone at risk. If you think we got it wrong, reply to that message or write to the same address, and we'll look at it again. A person, not an automated system, makes these decisions. You can also go to court.\n\n## Snapreel Pro\n\nSnapreel Pro is an auto-renewing subscription, monthly or yearly, sold by Apple through the App Store. The price in your currency, the length of any free trial, and what each plan includes are shown before you buy.\n\n- Payment is charged to your Apple Account when you confirm the purchase, or when a free trial ends. Any unused part of a free trial ends when you buy a subscription.\n- The subscription renews automatically at the same price and for the same period unless you cancel at least 24 hours before the current period ends.\n- Manage or cancel it in the Settings app › your name › Subscriptions. If you cancel, Pro continues until the end of the period you've paid for.\n- Apple sells the subscription, so refunds are handled by Apple under its policies, at [reportaproblem.apple.com](https://reportaproblem.apple.com). If you live in the EU or the UK, you may also have a right to cancel within 14 days of buying, which Apple handles in the same place.\n- Pro is linked to the Snapreel account you were signed in to when you bought it, and also works on the web dashboard at snapreel.video. It can't be bought on the website.\n- Deleting your Snapreel account doesn't cancel the subscription.\n\nOn the free plan you can have 25 active share links, each up to 5 minutes, played at 720p. Pro has no limit on the number of links; each one can be up to 2 hours and 2 GB, played at up to 1080p. If use of your account starts to harm the service for others, for example automated mass uploads, we'll contact you before limiting it.\n\nIf your subscription ends, your links keep working, but Pro extras such as downloads, your button and colour, and detailed insights switch off, and new links follow the free plan's limits. Passwords and expiry dates you've already set stay in place. We may change prices or what Pro includes; Apple will tell you before a price increase applies to you, and you can cancel before it does.\n\n## Features provided by iOS\n\nSnapreel relies on features built into iOS, such as screen recording, speech recognition and, on supported iPhones, Apple Intelligence. What they can do depends on your iPhone, its settings and your language, and some may not be available on every device.\n\n## Changes and availability\n\nWe may update Snapreel, change or remove features, or stop offering it. If we stop offering share links, we'll give you at least 30 days' notice so you can keep copies, and if you've paid for a period of Pro we can't provide, you can ask Apple for a refund. When these terms change, we'll update the date at the top, and tell you in the app or by email before a change that matters takes effect. Using Snapreel after a change means you accept the updated terms; if you don't, you can stop using Snapreel and delete your account.\n\n## No warranty\n\nSnapreel is provided \"as is\" and \"as available\". As far as the law allows, we don't promise that it will be free of errors, work without interruption, or never lose a recording or a link. Please keep copies of anything that matters to you, for example by saving it to Photos.\n\n## Limits on our liability\n\nAs far as the law allows, we aren't liable for indirect or consequential loss, or for loss of data, arising from your use of Snapreel. Our total liability for any claim is limited to the amount you paid for Snapreel in the 12 months before the claim.\n\nNothing in these terms limits any liability that can't be limited by law, such as for death or personal injury caused by negligence, or for fraud, or takes away your rights as a consumer under the law where you live.\n\n## Ending these terms\n\nYou can stop using Snapreel at any time by deleting your account and the app. We may suspend or close your account if you seriously or repeatedly break these terms, or if the law requires it; we'll tell you why, as described above. These terms then end, except the parts meant to continue (such as the limits on liability).\n\n## Apple\n\nThese terms are between you and us, not Apple. Apple isn't responsible for Snapreel or its content, and has no obligation to provide maintenance or support for it; please contact us for support.\n\n- If the app fails to conform to any applicable warranty, you may tell Apple, and Apple will refund the price you paid for the app, if any. As far as the law allows, Apple has no other warranty obligation for the app.\n- Apple isn't responsible for any claims by you or anyone else about the app or your use of it, including product liability claims, claims that it fails to meet a legal or regulatory requirement, and claims under consumer protection, privacy or similar laws.\n- If someone claims that the app or your use of it infringes their intellectual property rights, we, not Apple, are responsible for investigating, defending, settling and discharging that claim.\n- You confirm that you aren't in a country subject to a U.S. Government embargo or designated as \"terrorist supporting\", and that you aren't on any U.S. Government list of prohibited or restricted parties.\n- You must follow any third-party terms that apply when you use Snapreel, such as your mobile or internet provider's.\n- Apple and its subsidiaries are third-party beneficiaries of these terms and may enforce them against you.\n\n## Governing law and disputes\n\nThese terms are governed by the laws of Bangladesh, and the courts of Bangladesh can hear disputes about them. If you're a consumer, this doesn't take away the protection of the mandatory laws of the country where you live, and you can also bring a claim in the courts there. Please write to us first; most problems can be sorted out by email.\n\n## Contact\n\nQuestions about these terms? Write to Rezan Ferdous, Enayetpur, Sirajganj 6751, Bangladesh, or [support@snapreel.video](mailto:support@snapreel.video).\n";
