import Contacts

// A number typed without a country code gets the calling code of the region the person's
// Contacts settings use, so "9876543210" in India matches "+91 98765 43210" on the card.
// The app and the extension read the same setting, so both mint the same value IDs.
public enum PhoneRegion {
    public static let current = CNContactsUserDefaults.shared().countryCode.lowercased()

    static let nanpCode = "1"
    static let minNationalDigits = 7

    private static let nanpRegions: Set<String> = [
        "us", "ca", "pr", "gu", "vi", "as", "mp", "ag", "ai", "bb", "bm", "bs", "dm", "do",
        "gd", "jm", "kn", "ky", "lc", "ms", "sx", "tc", "tt", "vc", "vg"
    ]

    private static let codes: [String: String] = [
        "gb": "44", "ie": "353", "fr": "33", "de": "49", "es": "34", "it": "39", "pt": "351",
        "nl": "31", "be": "32", "lu": "352", "ch": "41", "at": "43", "dk": "45", "se": "46",
        "no": "47", "fi": "358", "is": "354", "pl": "48", "cz": "420", "sk": "421", "hu": "36",
        "ro": "40", "bg": "359", "gr": "30", "tr": "90", "il": "972", "ae": "971", "sa": "966",
        "eg": "20", "za": "27", "ng": "234", "ke": "254", "in": "91", "pk": "92", "bd": "880",
        "lk": "94", "cn": "86", "hk": "852", "tw": "886", "jp": "81", "kr": "82", "sg": "65",
        "my": "60", "th": "66", "vn": "84", "ph": "63", "id": "62", "au": "61", "nz": "64",
        "mx": "52", "br": "55", "ar": "54", "cl": "56", "co": "57", "pe": "51", "ru": "7",
        "ua": "380"
    ]

    static func callingCode(_ region: String) -> String? {
        let region = region.lowercased()
        return nanpRegions.contains(region) ? nanpCode : codes[region]
    }
}

enum StreetWords {
    static let short: [String: String] = [
        "avenue": "ave", "av": "ave", "street": "st", "road": "rd", "boulevard": "blvd",
        "drive": "dr", "lane": "ln", "court": "ct", "place": "pl", "square": "sq",
        "terrace": "ter", "circle": "cir", "highway": "hwy", "parkway": "pkwy",
        "north": "n", "south": "s", "east": "e", "west": "w",
        "suite": "#", "ste": "#", "apartment": "#", "apt": "#", "unit": "#"
    ]
}
