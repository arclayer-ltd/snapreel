# Session A: requests for shared code

## 1. Open Settings at a given page (router + shell)

E needs "storage low" in the feed to open Settings › Storage, and B's out-of-space saving state
links to Settings › Storage. `SettingsView` already accepts a starting path
(`SettingsView(initialPath: [SettingsPage])`, `SettingsPage` in `Features/Settings/SettingsView.swift`),
but the shell always presents it at the root.

`App/AppRouter.swift`:

```swift
/// Pages pushed when Settings opens (empty = the root).
@Published var settingsPath: [SettingsPage] = []

/// Opens the Settings sheet, optionally at a page: `router.openSettings(.storage)`.
func openSettings(_ page: SettingsPage? = nil) {
    settingsPath = page.map { [$0] } ?? []
    isSettingsPresented = true
}
```

`App/MainShell.swift`, the Settings sheet:

```swift
.sheet(isPresented: $router.isSettingsPresented) {
    SettingsView(initialPath: router.settingsPath)
        .environmentObject(library)
        .environmentObject(settings)
        .environmentObject(router)
}
```

`AppRouter.open(videoID:)` already sets `isSettingsPresented = false`; nothing else changes.
Until this lands, debug entries can use `SettingsDebugHost(path:)` (DEBUG only, in
`Features/Onboarding/StartDebugScreens.swift`), which presents the real `SettingsView` over the shell.

## 2. Light appearance for the whole app

Light screens use fixed colours (`srCanvas`, `srSurface`, `srText`), but system text such as
navigation titles follows the phone's appearance, so in Dark Mode the titles turn white on the light
canvas. Suggest `INFOPLIST_KEY_UIUserInterfaceStyle = Light` in both Snapreel build configurations
(dark screens already force `.preferredColorScheme(.dark)` for their own presentation).

Workaround in place: `SettingsView` and the "Mail isn't set up" sheet apply
`.preferredColorScheme(.light)` to their own sheet. `OnboardingFlow` applies
`.preferredColorScheme(.dark)` so the status bar is light over the dark page; it goes away when
onboarding ends.
