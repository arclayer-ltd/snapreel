import Foundation

/// What the person said they'll use Snapreel for (onboarding question).
enum UseCase: String, Codable, CaseIterable, Identifiable {
    case work
    case education
    case personal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .work: return "Work"
        case .education: return "School and teaching"
        case .personal: return "Just for me"
        }
    }

    var hint: String {
        switch self {
        case .work: return "Walk through a bug, give design feedback or send an update instead of a meeting."
        case .education: return "Explain a problem step by step, record a lesson or show your working."
        case .personal: return "Show family how to do something on their phone, or keep a video diary."
        }
    }

    var systemImage: String {
        switch self {
        case .work: return "briefcase.fill"
        case .education: return "graduationcap.fill"
        case .personal: return "heart.fill"
        }
    }
}

enum RecordingQuality: String, Codable, CaseIterable, Identifiable {
    case standard = "720p"
    case high = "1080p"
    case max = "4K"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: return "720p"
        case .high: return "1080p"
        case .max: return "4K"
        }
    }

    var detail: String {
        switch self {
        case .standard: return "Smallest files, about 40 MB a minute"
        case .high: return "Sharp on any screen, about 90 MB a minute"
        case .max: return "Back camera only, about 300 MB a minute"
        }
    }
}

enum CountdownLength: Int, Codable, CaseIterable, Identifiable {
    case off = 0
    case three = 3
    case five = 5
    case ten = 10

    var id: Int { rawValue }

    var label: String { self == .off ? "Off" : "\(rawValue) seconds" }
}

enum CameraSide: String, Codable, CaseIterable, Identifiable {
    case front
    case back

    var id: String { rawValue }
    var label: String { self == .front ? "Front" : "Back" }
}

/// Settings > Appearance. `system` follows the iPhone's Light or Dark setting. Every screen
/// follows it, the recorder and the player included; only the picture (camera, video) is dark.
enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Match iPhone"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var detail: String {
        switch self {
        case .system: return "Switches with your iPhone's Light and Dark setting"
        case .light: return "Always light"
        case .dark: return "Always dark"
        }
    }

    var systemImage: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}
