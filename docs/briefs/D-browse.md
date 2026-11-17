# Session D: home, library, folders, tags, search

Read `docs/briefs/COMMON.md` first. You own `Snapreel/Features/Home/`, `Snapreel/Features/Library/`,
`Snapreel/Features/Search/`. Tab roots live inside the shell's `NavigationStack`; use large
navigation titles and `.settingsToolbar()` for the gear. Light surfaces (`.srCanvas` background,
white cards).

## Screens

| Debug id(s) | Screen | Reference |
|---|---|---|
| `home.filled` `home.empty` | Home: time-of-day greeting as the large title ("Good morning", "Good afternoon", "Good evening", "Up late?"), rows Watch Later (count) and History (count) pushing `.watchLater` / `.history`, a "From my library" horizontal rail of video cards with See all (switches to Library tab), and a "Recently watched" rail. Empty: an inviting first-recording panel with "Start a recording" (`router.record()`), plus empty versions of the rails that don't feel broken. Tapping a card plays it (`router.play`). | appstore-01, mobbin 79dd23c0, a001ec8d |
| `home.history` `home.history.empty` | Watch history list (most recent first, with progress bars showing how far through), swipe to remove from history (`library.update { $0.lastWatchedAt = nil }`). Empty: `CharacterView(.emptyWatch)`. | mobbin 4836687a, 69fec831 |
| `home.later` `home.later.empty` | Watch later list, swipe to remove. Empty: `CharacterView(.emptyWatch)` with how to add. | appstore-01 row; designed fresh |
| `lib.videos` `lib.videos.empty` | Library, My videos tab (`UnderlineTabs` My videos / Folders): video cards with thumbnail (`VideoThumbnail`, duration badge), title, age, and note and reaction counts; a "…" button per card with the row actions; saving/failed cards show their state with Retry (call `PendingImports.resumeInterruptedSaves` or open the recorder's saving screen; ask the lead if unsure). Sort menu (newest, oldest, longest, title). Empty: `CharacterView(.emptyLibrary)` + "Start a recording". | mobbin 842c0ed9, eface933, appstore-06 |
| `lib.folders` `lib.folders.empty` | Folders tab: folder cards (name, count, updated age, first thumbnails), New folder button. Empty state with New folder. | mobbin 8815cad9 |
| `lib.folder` | Folder detail: its videos, rename/delete in a menu (delete moves videos back to My videos, say so), empty state. | designed fresh |
| `lib.folder.editor` | New / rename folder sheet: name field, validation (not empty, not a duplicate), Save. | designed fresh |
| `lib.move` | Move to folder sheet: "No folder" plus folders with the current one checked, New folder inline. | designed fresh |
| `lib.tags` | Tag editor sheet: current tags as removable chips, field to add (return adds), suggestions from `library.allTags`. | designed fresh |
| `lib.actions` | Video actions sheet from a card's "…": edit title (`TitleEditorSheet`), save to Photos (`.saveToPhotos`), share (`.shareVideo`), move to folder, edit tags, watch later toggle, delete with confirm. Your own layout (e.g. a header with thumbnail and title, then actions). | mobbin 5c3f6863 |
| `search.idle` | Search tab: large title, search field ("Titles, folders, tags or words said"), idle state with recent searches (stored locally, clearable) and tag chips to search by. | mobbin 2ba59348 |
| `search.results` `search.typing` `search.none` | Results as you type, grouped: Videos (title matches), Folders, Tags, Said in the video (transcript matches with the matching line and its timestamp; tapping plays from that time via `router.play(id, at:)`). Highlight the matched text. No-results state. `search.typing` shows the keyboard up with a partial query. | mobbin dc34fe74, d9ee7199 |

Search runs in memory over `library` (titles, folder names, tags, transcript segments),
case- and diacritic-insensitive. `FolderDetailView(folderID:)`, `WatchLaterView()`,
`WatchHistoryView()`, `HomeView()`, `LibraryView()`, `SearchView()` keep their signatures.
Share a `VideoCard` view between home rails, library and folder lists (your folder).
