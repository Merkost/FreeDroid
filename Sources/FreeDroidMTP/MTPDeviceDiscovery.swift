import Foundation
import CLibmtp

public actor MTPDeviceDiscovery {
    private let runtime: MTPRuntime

    public init(runtime: MTPRuntime) {
        self.runtime = runtime
    }

    public func detect() async throws -> [MTPRawDevice] {
        await runtime.ensureInitialized()

        var rawPtr: UnsafeMutablePointer<LIBMTP_raw_device_t>?
        var count: Int32 = 0
        let result = MTPStderrSilencer.run {
            LIBMTP_Detect_Raw_Devices(&rawPtr, &count)
        }

        defer { if let ptr = rawPtr { free(ptr) } }

        switch result {
        case LIBMTP_ERROR_NONE:
            break
        case LIBMTP_ERROR_NO_DEVICE_ATTACHED:
            return []
        default:
            throw MTPSessionError.operationFailed(message: "Detect_Raw_Devices=\(result.rawValue)")
        }

        guard let ptr = rawPtr, count > 0 else { return [] }

        var devices: [MTPRawDevice] = []
        for idx in 0..<Int(count) {
            let raw = ptr.advanced(by: idx).pointee
            let vendorName = raw.device_entry.vendor.map { String(cString: $0) }
            let productName = raw.device_entry.product.map { String(cString: $0) }
            devices.append(MTPRawDevice(
                vendorID: UInt16(raw.device_entry.vendor_id),
                productID: UInt16(raw.device_entry.product_id),
                busLocation: raw.bus_location,
                devnum: raw.devnum,
                vendorName: vendorName,
                productName: productName
            ))
        }
        return devices
    }
}
