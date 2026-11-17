"""Single source for the screen plan. Run: python -I scripts/plan_data.py
Writes docs/PLAN-screens.md (table) and refs/index.json (screen -> reference images).

Reference ids: Mobbin screen ids are the first 8 hex characters of files in
refs/mobbin/screens/; "appstore-0N" are refs/appstore/appstore-0N.png.
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# (id, group, owner, name, states, refs, server_only_refs_note)
# id = DebugScreen id of the screen's main state; states list the extra debug ids.
SCREENS = [
    # Getting started (A)
    ("start.splash", "Getting started", "A", "Splash", [], ["f475b086"], ""),
    ("start.welcome", "Getting started", "A", "Welcome (animated characters)", [], ["0ce2a2f6"], "Loom's welcome is its carousel with Sign in / Sign up; Snapreel has no account, so one Get started button."),
    ("start.intro.1", "Getting started", "A", "Intro slides", ["start.intro.2", "start.intro.3"], ["0ce2a2f6", "38ff4bf6", "8b5b84cc"], ""),
    ("start.use", "Getting started", "A", "What will you use it for", ["start.use.selected"], ["3812ca86", "9520b8b2"], ""),
    ("start.tour.intro", "Getting started", "A", "Guided tour", ["start.tour.1", "start.tour.2", "start.tour.3", "start.tour.permission", "start.tour.4"], ["19689a04", "8cf23f32", "ae0b8ff4", "6ad134c1", "83ffab4c", "55a17d4d"], ""),
    # Home (D)
    ("home.filled", "Home", "D", "Home", ["home.empty"], ["appstore-01", "79dd23c0", "a001ec8d"], ""),
    ("home.history", "Home", "D", "Watch history", ["home.history.empty"], ["4836687a", "69fec831"], ""),
    ("home.later", "Home", "D", "Watch later", ["home.later.empty"], ["appstore-01"], "Loom shows only the Watch Later row on Home; the list itself is designed fresh."),
    # Record (B)
    ("rec.shell", "Record", "B", "Recorder shell with mode switch", ["rec.shell.audio", "rec.shell.screen"], ["appstore-02"], ""),
    ("rec.primer", "Record", "B", "Permission primer", ["rec.primer.denied"], ["c0ee6731", "565c5843", "8c0ebeed"], ""),
    ("rec.camera", "Record", "B", "Camera viewfinder", [], ["appstore-02"], ""),
    ("rec.camera.recording", "Record", "B", "Camera recording", ["rec.camera.paused", "rec.camera.countdown"], [], "designed fresh"),
    ("rec.audio.recording", "Record", "B", "Audio recording (live waveform)", [], [], "designed fresh"),
    ("rec.screen.tutorial.1", "Record", "B", "Screen tutorial", ["rec.screen.tutorial.2", "rec.screen.tutorial.3"], ["8a4bd556", "9873040f", "9e42071f"], ""),
    ("rec.broadcast", "Record", "B", "Broadcast step", ["rec.broadcast.unavailable"], ["fe567cf9", "1245d328"], ""),
    ("rec.screen.recording", "Record", "B", "Screen recording in progress", [], ["8f0f7c0f", "15f044ca", "3dfe7131"], ""),
    ("rec.settings", "Record", "B", "Recording settings", [], ["appstore-02"], "Gear on Loom's current camera screen; contents designed fresh."),
    ("rec.notes", "Record", "B", "Speaker notes", ["rec.notes.overlay"], ["appstore-02"], "Pencil-in-square on Loom's current camera screen; contents designed fresh."),
    ("rec.import", "Record", "B", "Photo library import", [], ["appstore-02"], "Photo icon on Loom's current camera screen; flow designed fresh."),
    ("rec.review", "Record", "B", "Review after recording", ["rec.review.delete"], ["c0702bfb", "9bed6b10", "4f5b94d4"], ""),
    ("rec.title", "Record", "B", "Title editor", [], ["4f4426ef", "18dfff18"], ""),
    ("rec.share", "Record", "B", "Share sheet", [], ["96967148", "cafdf5de"], "Loom shares a link (server-only); Snapreel shares the file."),
    ("rec.saving", "Record", "B", "Saving progress", ["rec.saving.failed", "rec.saving.nospace"], [], "designed fresh (Loom uploads)"),
    # Library (D)
    ("lib.videos", "Library", "D", "My videos", ["lib.videos.empty"], ["842c0ed9", "eface933", "appstore-06"], ""),
    ("lib.folders", "Library", "D", "Folders", ["lib.folders.empty"], ["8815cad9"], ""),
    ("lib.folder", "Library", "D", "Folder detail", [], [], "designed fresh"),
    ("lib.folder.editor", "Library", "D", "New or rename folder", [], [], "designed fresh"),
    ("lib.move", "Library", "D", "Move to folder", [], [], "designed fresh"),
    ("lib.tags", "Library", "D", "Tag editor", [], [], "designed fresh"),
    ("lib.actions", "Library", "D", "Video actions sheet", [], ["5c3f6863"], ""),
    # Video (C)
    ("video.player", "Video", "C", "Player", [], ["333244de", "2633dd18", "appstore-04"], ""),
    ("video.fullscreen", "Video", "C", "Fullscreen player", [], [], "designed fresh"),
    ("video.pip", "Video", "C", "Picture-in-picture state", [], ["307833f4"], ""),
    ("video.speed", "Video", "C", "Speed menu", [], ["5bdf10e6", "7fbf9539"], ""),
    ("video.notes", "Video", "C", "Notes tab", ["video.notes.empty"], ["08b623c3", "dfc7a242", "68117697"], "Loom's activity is other people's comments (server-only); Snapreel shows your own notes."),
    ("video.transcript", "Video", "C", "Transcript tab", ["video.transcript.none"], ["1cf35f2e"], ""),
    ("video.details", "Video", "C", "Details and summary", [], ["333244de", "appstore-04"], ""),
    ("video.note.compose", "Video", "C", "Note composer", [], ["d8cee37f", "e835b4d8"], ""),
    ("video.note.edit", "Video", "C", "Edit note", [], ["66e3bbdc", "20d71ce8"], "Loom's reply composer is the craft reference."),
    ("video.reaction", "Video", "C", "Reaction overlay", [], ["69165b4c", "b670b4bf"], ""),
    ("video.emoji", "Video", "C", "Emoji picker", [], [], "designed fresh"),
    ("video.actions", "Video", "C", "Video actions", ["video.actions.delete"], ["5c3f6863"], ""),
    ("video.photos.permission", "Video", "C+E", "Save to Photos", ["video.photos.progress", "video.photos.saved"], ["7abeda8d"], ""),
    ("video.stats", "Video", "C", "Stats", [], ["4ebeb7dc", "c71f7bb9"], "Loom's insights are viewers (server-only); Snapreel's stats are on-device."),
    # Notifications (E)
    ("notif.feed", "Notifications", "E", "Notifications feed", ["notif.feed.empty"], ["baadcda8", "a7678dbf", "appstore-05"], "Loom's items are other people's activity (server-only); Snapreel lists what the app did."),
    # Search (D)
    ("search.idle", "Search", "D", "Search idle", [], ["2ba59348"], ""),
    ("search.results", "Search", "D", "Search results", ["search.typing", "search.none"], ["dc34fe74", "d9ee7199"], ""),
    # Settings
    ("settings.root", "Settings", "A", "Settings root", [], ["74aeb655"], ""),
    ("settings.notifications", "Settings", "E", "Notification settings", [], ["be1d5c1e", "6bf1eb6d"], ""),
    ("settings.recording", "Settings", "B", "Recording defaults", [], [], "designed fresh"),
    ("settings.storage", "Settings", "E", "Storage", ["settings.storage.confirm", "settings.storage.done"], ["3792bec9", "0adb4039"], "Loom's delete-account screens are the craft reference for delete-all-data."),
    ("help.home", "Settings", "A", "Help centre", [], ["f9c3e1f6", "49885582", "92adeabb"], ""),
    ("help.article", "Settings", "A", "Help article", [], ["5b3089b4"], ""),
    ("help.contact", "Settings", "A", "Contact support", [], ["f9c3e1f6"], "Compose icon in Loom's help header; form designed fresh."),
    ("legal.menu", "Settings", "A", "Legal menu", [], ["35a24f63"], ""),
    ("legal.terms", "Settings", "A", "Terms and privacy viewer", ["legal.privacy"], ["d2910d61", "dc86d237"], ""),
    ("legal.ack", "Settings", "A", "Acknowledgements", [], ["939b73c4"], ""),
]

# Loom flows and their Snapreel counterparts (ordered Snapreel debug ids, one per Loom step;
# None = that Loom step is server-only and has no counterpart).
FLOWS = {
    "01-onboarding": {"snapreel": ["start.splash", "start.intro.1", "start.intro.2", "start.intro.3", None, None, None, None, None, None, None, None, "start.use", "start.use.selected", "start.tour.intro", "start.tour.1", "start.tour.2", "start.tour.3", "start.tour.permission", "start.tour.4", "home.empty"], "note": "Loom steps 5-12 are account sign-up and email verification (server-only)."},
    "03-home": {"snapreel": ["home.empty", "home.history.empty"]},
    "04-starting-a-recording": {"snapreel": ["home.empty", "rec.primer", "rec.primer", "rec.primer", "rec.screen.tutorial.1", "rec.screen.tutorial.2", "rec.screen.tutorial.3", "rec.broadcast", "rec.broadcast.unavailable", "rec.screen.recording", None, "rec.screen.recording", "rec.screen.recording", "rec.review", "rec.review", "rec.title", "rec.title", "rec.review", "rec.share", None, "home.filled"], "note": "Step 11 is the content being recorded (another app); step 20 is Loom's link-copied toast (server-only). System permission alerts and the system broadcast sheet are iOS UI over Snapreel's primer and broadcast step."},
    "05-video-detail": {"snapreel": ["home.filled", "video.player", "video.notes", "video.transcript.none"]},
    "06-responding-to-the-video": {"snapreel": ["video.player", "video.reaction", "video.reaction"]},
    "07-commenting-on-the-video": {"snapreel": ["video.notes", "video.note.compose", "video.note.compose", "video.notes", "home.filled"]},
    "09-setting-video-speed": {"snapreel": ["video.player", "video.speed", "video.player"]},
    "10-picture-in-picture-mode": {"snapreel": ["video.player", "video.pip"]},
    "11-downloading-a-video": {"snapreel": ["video.player", "video.actions", "video.photos.permission", "video.photos.saved"]},
    "14-library": {"snapreel": ["lib.videos", "lib.videos", "lib.folders"]},
    "15-notifications": {"snapreel": ["notif.feed", "notif.feed"]},
    "16-search": {"snapreel": ["search.idle"]},
    "17-searching-for-title-folder-tag-or-person": {"snapreel": ["search.idle", "search.typing", "search.results"]},
    "18-settings": {"snapreel": ["notif.feed", "settings.root"]},
    "19-help-and-support": {"snapreel": ["settings.root", "help.home", "help.home", "help.home", "help.home"]},
    "20-editing-notification-settings": {"snapreel": ["settings.root", "settings.notifications", "settings.notifications", None], "note": "Step 4 is a network error banner (server-only)."},
    "21-legal": {"snapreel": ["settings.root", "legal.menu"]},
    "22-terms-and-conditions": {"snapreel": ["legal.menu", "legal.terms"]},
    "23-privacy-policy": {"snapreel": ["legal.menu", "legal.privacy"]},
    "24-acknowledgements": {"snapreel": ["legal.menu", "legal.ack"]},
    "26-deleting-account": {"snapreel": ["settings.storage", "settings.storage", "settings.storage.confirm", None, "settings.storage.done"], "note": "Snapreel has no account; delete-all-data is the counterpart. Step 4 is a server error."},
}
SERVER_ONLY_FLOWS = {
    "02-logging-in": "accounts",
    "08-replying-to-thread": "other people's comment threads",
    "12-engagement-insights": "viewer insights (Snapreel's stats screen is compared per screen only)",
    "13-user-stats": "per-viewer stats",
    "25-logging-out": "accounts",
}


def resolve(ref):
    if ref.startswith("appstore-"):
        return f"refs/appstore/{ref}.png"
    folder = os.path.join(ROOT, "refs", "mobbin", "screens")
    if os.path.isdir(folder):
        for name in os.listdir(folder):
            if name.startswith(ref):
                return f"refs/mobbin/screens/{name}"
    return f"refs/mobbin/screens/{ref}*.png"


def main():
    index = {"screens": [], "flows": {}, "serverOnlyFlows": SERVER_ONLY_FLOWS}
    rows = []
    for sid, group, owner, name, states, refs, note in SCREENS:
        entry = {"id": sid, "group": group, "owner": owner, "name": name, "states": states,
                 "references": [resolve(r) for r in refs],
                 "reference": "no reference, designed fresh" if not refs else None, "note": note}
        index["screens"].append(entry)
        ref_text = ", ".join(refs) if refs else "no reference, designed fresh"
        rows.append(f"| {len(rows) + 1} | {group} | `{sid}` | {name} | {', '.join('`' + s + '`' for s in states) or '-'} | {owner} | {ref_text} | {note} |")
    for flow, data in FLOWS.items():
        index["flows"][flow] = data
    os.makedirs(os.path.join(ROOT, "refs"), exist_ok=True)
    with open(os.path.join(ROOT, "refs", "index.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(index, f, indent=1)
    table = ["| # | Group | Debug id | Screen | Extra states | Owner | Reference | Notes |",
             "|---|---|---|---|---|---|---|---|"] + rows
    with open(os.path.join(ROOT, "docs", "PLAN-screens.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write("# Screen plan (generated by scripts/plan_data.py)\n\n")
        f.write("Every planned screen, its debug id (`-screen <id>`), extra states, owning session and Loom reference. ")
        f.write("Reference ids are Mobbin screen-id prefixes (refs/mobbin/screens/) or App Store screenshots (refs/appstore/).\n\n")
        f.write("\n".join(table) + "\n")
    print(len(SCREENS), "screens,", sum(1 + len(s[4]) for s in SCREENS), "debug states,", len(FLOWS), "flows")


if __name__ == "__main__":
    sys.exit(main())
