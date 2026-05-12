import Foundation

public enum AndroidVendorIDs {
    public static let knownVendors: Set<UInt16> = [
        0x18D1,
        0x04E8,
        0x0BB4,
        0x054C,
        0x22B8,
        0x2717,
        0x2A70,
        0x05C6,
        0x12D1,
        0x1004,
        0x17EF,
        0x22D9,
        0x2D95,
        0x35F5,
        0x0FCE,
        0x0E79,
        0x0489,
        0x091E,
        0x19D2,
        0x1F3A
    ]

    private static let vendorNames: [UInt16: String] = [
        0x18D1: "Google",
        0x04E8: "Samsung",
        0x0BB4: "HTC",
        0x054C: "Sony",
        0x22B8: "Motorola",
        0x2717: "Xiaomi",
        0x2A70: "OnePlus",
        0x05C6: "OnePlus / Qualcomm",
        0x12D1: "Huawei",
        0x1004: "LG",
        0x17EF: "Lenovo",
        0x22D9: "Oppo",
        0x2D95: "Vivo",
        0x35F5: "Nothing",
        0x0FCE: "Sony Mobile",
        0x0E79: "Archos",
        0x0489: "Foxconn",
        0x091E: "Garmin-Asus",
        0x19D2: "ZTE",
        0x1F3A: "Allwinner"
    ]

    public static func isAndroidVendor(_ vendorID: UInt16) -> Bool {
        knownVendors.contains(vendorID)
    }

    public static func vendorName(for vendorID: UInt16) -> String? {
        vendorNames[vendorID]
    }
}
