import Foundation

/// One emoji with a spoken name and extra search words.
struct EmojiItem: Hashable, Identifiable {
    let emoji: String
    let name: String
    let keywords: String

    var id: String { emoji }

    /// Lower-cased, accent-free text to search in.
    var searchText: String {
        (name + " " + keywords).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

enum EmojiCategory: String, CaseIterable, Identifiable {
    case smileys
    case gestures
    case hearts
    case animals
    case food
    case activities
    case travel
    case objects
    case symbols

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smileys: return "Faces"
        case .gestures: return "Hands and people"
        case .hearts: return "Hearts and sparks"
        case .animals: return "Animals and nature"
        case .food: return "Food and drink"
        case .activities: return "Celebrations and play"
        case .travel: return "Travel and places"
        case .objects: return "Things"
        case .symbols: return "Symbols"
        }
    }

    /// Chip label.
    var shortTitle: String {
        switch self {
        case .smileys: return "Faces"
        case .gestures: return "Hands"
        case .hearts: return "Hearts"
        case .animals: return "Nature"
        case .food: return "Food"
        case .activities: return "Play"
        case .travel: return "Travel"
        case .objects: return "Things"
        case .symbols: return "Symbols"
        }
    }

    var symbol: String {
        switch self {
        case .smileys: return "face.smiling"
        case .gestures: return "hand.thumbsup"
        case .hearts: return "heart"
        case .animals: return "leaf"
        case .food: return "fork.knife"
        case .activities: return "party.popper"
        case .travel: return "car"
        case .objects: return "lightbulb"
        case .symbols: return "number"
        }
    }
}

/// Snapreel's built-in emoji list, so reacting never needs the emoji keyboard.
enum EmojiCatalog {
    /// The six in the reaction bar and the reaction grid.
    static let quick = ["👍", "❤️", "😂", "😮", "🔥", "👏"]

    static func items(in category: EmojiCategory) -> [EmojiItem] {
        all[category] ?? []
    }

    static func search(_ query: String) -> [EmojiItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        guard !needle.isEmpty else { return [] }
        var seen = Set<String>()
        return EmojiCategory.allCases
            .flatMap { items(in: $0) }
            .filter { $0.emoji == needle || $0.searchText.contains(needle) }
            .filter { seen.insert($0.emoji).inserted }
    }

    /// Spoken name for VoiceOver ("thumbs up").
    static func name(for emoji: String) -> String {
        names[emoji] ?? emoji
    }

    private static let names: [String: String] = {
        var map: [String: String] = [:]
        for list in all.values {
            for item in list where map[item.emoji] == nil { map[item.emoji] = item.name }
        }
        return map
    }()

    private static func e(_ emoji: String, _ name: String, _ keywords: String = "") -> EmojiItem {
        EmojiItem(emoji: emoji, name: name, keywords: keywords)
    }

    private static let all: [EmojiCategory: [EmojiItem]] = [
        .smileys: smileys,
        .gestures: gestures,
        .hearts: hearts,
        .animals: animals,
        .food: food,
        .activities: activities,
        .travel: travel,
        .objects: objects,
        .symbols: symbols,
    ]

    private static let smileys: [EmojiItem] = [
        e("😀", "grinning face", "smile happy"),
        e("😃", "grinning face with big eyes", "smile happy"),
        e("😄", "grinning face with smiling eyes", "smile happy laugh"),
        e("😁", "beaming face", "grin happy"),
        e("😆", "laughing face", "laugh lol"),
        e("😅", "grinning face with sweat", "phew nervous laugh"),
        e("🤣", "rolling on the floor laughing", "lol rofl"),
        e("😂", "face with tears of joy", "laugh lol funny"),
        e("🙂", "slightly smiling face", "smile"),
        e("🙃", "upside-down face", "silly sarcasm"),
        e("🫠", "melting face", "awkward hot"),
        e("😉", "winking face", "wink"),
        e("😊", "smiling face with smiling eyes", "blush happy"),
        e("😇", "smiling face with halo", "angel innocent"),
        e("🥰", "smiling face with hearts", "love adore"),
        e("😍", "smiling face with heart eyes", "love crush"),
        e("🤩", "star-struck", "wow amazing"),
        e("😘", "face blowing a kiss", "kiss love"),
        e("😋", "face savouring food", "yum tasty"),
        e("😛", "face with tongue", "cheeky"),
        e("😜", "winking face with tongue", "joke silly"),
        e("🤪", "zany face", "crazy silly"),
        e("🤗", "hugging face", "hug thanks"),
        e("🤭", "face with hand over mouth", "oops giggle"),
        e("🤫", "shushing face", "quiet secret"),
        e("🤔", "thinking face", "hmm question consider"),
        e("🤐", "zipper-mouth face", "secret quiet"),
        e("🤨", "face with raised eyebrow", "doubt sceptical"),
        e("😐", "neutral face", "meh"),
        e("😑", "expressionless face", "blank"),
        e("😶", "face without mouth", "speechless"),
        e("😏", "smirking face", "smug"),
        e("😒", "unamused face", "meh annoyed"),
        e("🙄", "face with rolling eyes", "eye roll"),
        e("😬", "grimacing face", "awkward yikes"),
        e("😮‍💨", "face exhaling", "sigh relief"),
        e("😌", "relieved face", "calm"),
        e("😔", "pensive face", "sad"),
        e("😪", "sleepy face", "tired"),
        e("😴", "sleeping face", "zzz tired bored"),
        e("😷", "face with medical mask", "sick ill"),
        e("🤯", "exploding head", "mind blown shocked"),
        e("🥳", "partying face", "party celebrate"),
        e("😎", "smiling face with sunglasses", "cool"),
        e("🤓", "nerd face", "geek smart"),
        e("🧐", "face with monocle", "inspect curious"),
        e("😕", "confused face", "unsure"),
        e("😟", "worried face", "concern"),
        e("😮", "face with open mouth", "wow surprise"),
        e("😯", "hushed face", "surprise"),
        e("😲", "astonished face", "shock wow"),
        e("😳", "flushed face", "embarrassed"),
        e("🥺", "pleading face", "please puppy eyes"),
        e("😢", "crying face", "sad tear"),
        e("😭", "loudly crying face", "sob sad"),
        e("😱", "face screaming in fear", "scared shock"),
        e("😤", "face with steam from nose", "frustrated proud"),
        e("😡", "pouting face", "angry mad"),
        e("💀", "skull", "dead lol"),
        e("🤡", "clown face", "silly"),
        e("👻", "ghost", "boo spooky"),
        e("🤖", "robot", "bot machine"),
    ]

    private static let gestures: [EmojiItem] = [
        e("👍", "thumbs up", "yes like good agree"),
        e("👎", "thumbs down", "no dislike bad"),
        e("👏", "clapping hands", "applause bravo well done"),
        e("🙌", "raising hands", "hooray celebrate"),
        e("👐", "open hands", "hug"),
        e("🤝", "handshake", "deal agree"),
        e("🙏", "folded hands", "please thanks pray"),
        e("✌️", "victory hand", "peace"),
        e("🤞", "crossed fingers", "luck hope"),
        e("🤟", "love-you gesture", "love"),
        e("🤘", "sign of the horns", "rock"),
        e("👌", "OK hand", "perfect fine"),
        e("🤌", "pinched fingers", "chef kiss"),
        e("👈", "backhand index pointing left", "point left"),
        e("👉", "backhand index pointing right", "point right"),
        e("👆", "backhand index pointing up", "point up"),
        e("👇", "backhand index pointing down", "point down"),
        e("☝️", "index pointing up", "one first"),
        e("✋", "raised hand", "stop wait high five"),
        e("👋", "waving hand", "hello hi bye"),
        e("🤙", "call me hand", "shaka"),
        e("💪", "flexed biceps", "strong"),
        e("✍️", "writing hand", "write note"),
        e("👀", "eyes", "look watch see"),
        e("🧠", "brain", "smart think"),
        e("🫡", "saluting face", "yes sir respect"),
        e("🤷", "person shrugging", "dunno whatever"),
        e("🙋", "person raising hand", "question me"),
        e("🙇", "person bowing", "sorry thanks"),
        e("🤦", "person facepalming", "doh"),
    ]

    private static let hearts: [EmojiItem] = [
        e("❤️", "red heart", "love like"),
        e("🧡", "orange heart", "love"),
        e("💛", "yellow heart", "love"),
        e("💚", "green heart", "love"),
        e("💙", "blue heart", "love"),
        e("💜", "purple heart", "love"),
        e("🖤", "black heart", "love"),
        e("🤍", "white heart", "love"),
        e("🤎", "brown heart", "love"),
        e("💔", "broken heart", "sad heartbreak"),
        e("❤️‍🔥", "heart on fire", "passion love"),
        e("💕", "two hearts", "love"),
        e("💖", "sparkling heart", "love"),
        e("💯", "hundred points", "perfect 100 score"),
        e("💥", "collision", "boom"),
        e("💫", "dizzy", "star"),
        e("💤", "zzz", "sleep bored"),
        e("💬", "speech balloon", "comment talk"),
        e("💭", "thought balloon", "think"),
        e("✨", "sparkles", "new shiny magic"),
        e("🔥", "fire", "hot lit great"),
        e("⭐", "star", "favourite"),
        e("🌟", "glowing star", "shine"),
        e("⚡", "high voltage", "lightning fast"),
    ]

    private static let animals: [EmojiItem] = [
        e("🐶", "dog face", "puppy pet"),
        e("🐱", "cat face", "kitten pet"),
        e("🐭", "mouse face", "mouse"),
        e("🐰", "rabbit face", "bunny"),
        e("🦊", "fox", "fox"),
        e("🐻", "bear", "bear"),
        e("🐼", "panda", "panda"),
        e("🐨", "koala", "koala"),
        e("🐯", "tiger face", "tiger"),
        e("🦁", "lion", "lion"),
        e("🐮", "cow face", "cow"),
        e("🐷", "pig face", "pig"),
        e("🐸", "frog", "frog"),
        e("🐵", "monkey face", "monkey"),
        e("🙈", "see-no-evil monkey", "oops shy"),
        e("🐔", "chicken", "hen"),
        e("🐧", "penguin", "penguin"),
        e("🐦", "bird", "bird"),
        e("🦉", "owl", "wise night"),
        e("🦄", "unicorn", "magic"),
        e("🐝", "honeybee", "bee busy"),
        e("🐛", "bug", "caterpillar defect issue"),
        e("🦋", "butterfly", "pretty"),
        e("🐢", "turtle", "slow"),
        e("🐙", "octopus", "octopus"),
        e("🐬", "dolphin", "sea"),
        e("🐳", "spouting whale", "sea"),
        e("🌵", "cactus", "desert"),
        e("🌲", "evergreen tree", "tree forest"),
        e("🌱", "seedling", "grow new"),
        e("🍀", "four leaf clover", "luck"),
        e("🌸", "cherry blossom", "flower spring"),
        e("🌻", "sunflower", "flower"),
        e("🌈", "rainbow", "pride colour"),
        e("☀️", "sun", "sunny weather"),
        e("🌙", "crescent moon", "night"),
        e("⛅", "sun behind cloud", "weather"),
        e("🌧️", "cloud with rain", "rain weather"),
        e("❄️", "snowflake", "cold winter"),
        e("🌊", "water wave", "sea ocean"),
    ]

    private static let food: [EmojiItem] = [
        e("🍏", "green apple", "fruit"),
        e("🍎", "red apple", "fruit"),
        e("🍌", "banana", "fruit"),
        e("🍉", "watermelon", "fruit summer"),
        e("🍓", "strawberry", "fruit"),
        e("🍒", "cherries", "fruit"),
        e("🍑", "peach", "fruit"),
        e("🥑", "avocado", "fruit"),
        e("🍅", "tomato", "vegetable"),
        e("🌶️", "hot pepper", "spicy chilli"),
        e("🥕", "carrot", "vegetable"),
        e("🍞", "bread", "toast"),
        e("🥐", "croissant", "breakfast"),
        e("🧀", "cheese wedge", "cheese"),
        e("🍳", "cooking", "egg breakfast"),
        e("🍔", "hamburger", "burger"),
        e("🍟", "french fries", "chips"),
        e("🍕", "pizza", "slice"),
        e("🌮", "taco", "mexican"),
        e("🍣", "sushi", "japanese"),
        e("🍜", "steaming bowl", "noodles ramen"),
        e("🍿", "popcorn", "movie watch"),
        e("🍩", "doughnut", "donut sweet"),
        e("🍪", "cookie", "biscuit sweet"),
        e("🎂", "birthday cake", "birthday celebrate"),
        e("🍰", "shortcake", "cake sweet"),
        e("🍫", "chocolate bar", "sweet"),
        e("☕", "hot beverage", "coffee tea break"),
        e("🍵", "teacup without handle", "tea green"),
        e("🥤", "cup with straw", "drink soda"),
        e("🍺", "beer mug", "pint drink"),
        e("🍷", "wine glass", "drink"),
        e("🥂", "clinking glasses", "cheers toast"),
        e("🍾", "bottle with popping cork", "champagne celebrate"),
    ]

    private static let activities: [EmojiItem] = [
        e("🎉", "party popper", "celebrate congrats tada"),
        e("🎊", "confetti ball", "celebrate party"),
        e("🎈", "balloon", "party birthday"),
        e("🎁", "wrapped gift", "present birthday"),
        e("🏆", "trophy", "win winner champion"),
        e("🥇", "first place medal", "gold winner"),
        e("🏅", "sports medal", "award"),
        e("⚽", "football", "soccer sport"),
        e("🏀", "basketball", "sport"),
        e("🎾", "tennis", "sport"),
        e("🏓", "ping pong", "table tennis"),
        e("🎯", "bullseye", "target goal hit"),
        e("🎮", "video game", "controller play"),
        e("🎲", "game die", "dice chance"),
        e("🧩", "puzzle piece", "fit solve"),
        e("🎨", "artist palette", "art design colour"),
        e("🎬", "clapper board", "film movie action"),
        e("🎤", "microphone", "sing talk"),
        e("🎧", "headphone", "music listen"),
        e("🎸", "guitar", "music rock"),
        e("🎹", "musical keyboard", "piano music"),
        e("🥁", "drum", "drumroll music"),
        e("🏃", "person running", "run fast"),
        e("🚴", "person biking", "cycle bike"),
        e("🧘", "person in lotus position", "yoga calm"),
        e("🏊", "person swimming", "swim"),
    ]

    private static let travel: [EmojiItem] = [
        e("🚀", "rocket", "launch ship fast"),
        e("✈️", "aeroplane", "plane flight travel"),
        e("🚗", "car", "drive"),
        e("🚕", "taxi", "cab"),
        e("🚌", "bus", "travel"),
        e("🚆", "train", "rail"),
        e("🚲", "bicycle", "bike"),
        e("🛴", "kick scooter", "scooter"),
        e("⛵", "sailboat", "boat"),
        e("🚢", "ship", "boat"),
        e("🗺️", "world map", "map"),
        e("🧭", "compass", "direction"),
        e("🏠", "house", "home"),
        e("🏢", "office building", "work office"),
        e("🏫", "school", "class learn"),
        e("🏥", "hospital", "health"),
        e("🏖️", "beach with umbrella", "holiday"),
        e("🏔️", "snow-capped mountain", "mountain"),
        e("🏕️", "camping", "tent outdoors"),
        e("🌍", "globe showing Europe and Africa", "world earth"),
        e("🗽", "Statue of Liberty", "statue"),
        e("🎡", "ferris wheel", "fair fun"),
        e("🌃", "night with stars", "city night"),
        e("🌅", "sunrise", "morning"),
    ]

    private static let objects: [EmojiItem] = [
        e("📱", "mobile phone", "iphone"),
        e("💻", "laptop", "computer mac"),
        e("⌨️", "keyboard", "type"),
        e("🖥️", "desktop computer", "screen monitor"),
        e("🖨️", "printer", "print"),
        e("📷", "camera", "photo"),
        e("🎥", "movie camera", "video film record"),
        e("📺", "television", "tv watch"),
        e("⏰", "alarm clock", "time wake"),
        e("⏳", "hourglass not done", "wait time"),
        e("🔋", "battery", "power"),
        e("🔌", "electric plug", "power"),
        e("💡", "light bulb", "idea"),
        e("🔦", "torch", "flashlight light"),
        e("📚", "books", "read study"),
        e("📝", "memo", "note write"),
        e("✏️", "pencil", "write edit"),
        e("📌", "pushpin", "pin important"),
        e("📎", "paperclip", "attach"),
        e("✂️", "scissors", "cut"),
        e("🗂️", "card index dividers", "organise folder"),
        e("📅", "calendar", "date"),
        e("📈", "chart increasing", "up growth"),
        e("📉", "chart decreasing", "down"),
        e("📊", "bar chart", "stats data"),
        e("🔒", "locked", "private secure"),
        e("🔑", "key", "access"),
        e("🔧", "spanner", "wrench fix"),
        e("🔨", "hammer", "build fix"),
        e("🛠️", "hammer and spanner", "tools build"),
        e("💰", "money bag", "money"),
        e("💳", "credit card", "pay"),
        e("📦", "package", "box ship"),
        e("✉️", "envelope", "mail letter"),
        e("📣", "megaphone", "announce"),
        e("🔔", "bell", "notification"),
    ]

    private static let symbols: [EmojiItem] = [
        e("✅", "check mark button", "done yes tick"),
        e("☑️", "check box with check", "done tick"),
        e("✔️", "check mark", "done tick"),
        e("❌", "cross mark", "no wrong"),
        e("❎", "cross mark button", "no"),
        e("➕", "plus", "add"),
        e("➖", "minus", "remove"),
        e("❓", "question mark", "question"),
        e("❗", "exclamation mark", "important"),
        e("‼️", "double exclamation mark", "important"),
        e("⚠️", "warning", "careful"),
        e("🚫", "prohibited", "no"),
        e("⛔", "no entry", "stop"),
        e("🔴", "red circle", "red"),
        e("🟠", "orange circle", "orange"),
        e("🟡", "yellow circle", "yellow"),
        e("🟢", "green circle", "green go"),
        e("🔵", "blue circle", "blue"),
        e("🟣", "purple circle", "purple"),
        e("⬆️", "up arrow", "up"),
        e("⬇️", "down arrow", "down"),
        e("➡️", "right arrow", "next"),
        e("⬅️", "left arrow", "back"),
        e("🔁", "repeat button", "again loop"),
        e("🔄", "anticlockwise arrows", "refresh"),
        e("⏩", "fast-forward button", "skip"),
        e("⏪", "fast reverse button", "rewind"),
        e("⏸️", "pause button", "pause"),
        e("▶️", "play button", "play"),
        e("🆕", "NEW button", "new"),
        e("🆗", "OK button", "ok"),
        e("🆒", "COOL button", "cool"),
        e("🆘", "SOS button", "help"),
        e("♻️", "recycling symbol", "recycle"),
    ]
}

/// The last reactions you picked, newest first, kept on this iPhone for the picker.
enum EmojiRecents {
    private static let key = "player.recentEmoji"
    private static let limit = 16

    static func load() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func record(_ emoji: String) {
        var list = load().filter { $0 != emoji }
        list.insert(emoji, at: 0)
        UserDefaults.standard.set(Array(list.prefix(limit)), forKey: key)
    }
}
