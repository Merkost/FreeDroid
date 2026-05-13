import Foundation

public enum AndroidVendorIDs {
    private static let vendorNames: [UInt16: String] = [
        0x18D1: "Google",
        0x04E8: "Samsung",
        0x0BB4: "HTC",
        0x054C: "Sony",
        0x0FCE: "Sony Mobile",
        0x22B8: "Motorola",
        0x2717: "Xiaomi",
        0x2A40: "Xiaomi",
        0x2A70: "OnePlus",
        0x05C6: "Qualcomm",
        0x12D1: "Huawei",
        0x1004: "LG",
        0x17EF: "Lenovo",
        0x22D9: "Oppo",
        0x2A13: "Oppo",
        0x2D71: "Realme",
        0x2D95: "Vivo",
        0x35F5: "Nothing",
        0x2916: "HMD / Nokia",
        0x2BB8: "Honor",
        0x0421: "Nokia",
        0x0B05: "ASUS",
        0x18B1: "ASUS Padfone",
        0x16D5: "Acer Mobile",
        0x0E79: "Archos",
        0x0489: "Foxconn",
        0x2980: "Foxconn International",
        0x2B0E: "Foxconn",
        0x091E: "Garmin-Asus",
        0x1AF7: "Garmin",
        0x19D2: "ZTE",
        0x2A45: "ZTE",
        0x1F3A: "Allwinner",
        0x10A9: "Pantech",
        0x0B7E: "Yulong / Coolpad",
        0x1B8B: "Compal",
        0x055E: "TCL / Alcatel",
        0x1BBB: "T-Mobile / Alcatel",
        0x1782: "Spreadtrum / Unisoc",
        0x2782: "BLU",
        0x2A19: "BLU / Phicomm",
        0x0E8D: "MediaTek",
        0x297F: "Tecno / Infinix",
        0x29A9: "Tecno",
        0x2BC5: "Tinno / Wiko",
        0x2BC8: "Hisense",
        0x2C7C: "Quectel",
        0x29F1: "Cubot",
        0x046D: "Logitech",
        0x04DA: "Panasonic",
        0x04DD: "Sharp",
        0x1F85: "Sharp Mobile",
        0x0930: "Toshiba",
        0x0FCA: "RIM / BlackBerry",
        0x2244: "Kyocera",
        0x1949: "Lab126 (Amazon)",
        0x2421: "Wileyfox",
        0x2257: "Highscreen",
        0x1A0A: "Bird",
        0x1EBB: "Casio",
        0x1B7A: "Hama",
        0x2C8A: "Geeksphone",
        0x05E3: "Genesys Logic"
    ]

    public static let knownVendors: Set<UInt16> = Set(vendorNames.keys)

    public static func isAndroidVendor(_ vendorID: UInt16) -> Bool {
        knownVendors.contains(vendorID)
    }

    public static func vendorName(for vendorID: UInt16) -> String? {
        vendorNames[vendorID]
    }
}
