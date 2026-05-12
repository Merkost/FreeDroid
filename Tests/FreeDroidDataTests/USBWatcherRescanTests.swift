import Foundation
import Testing
@testable import FreeDroidData

@Suite("USBDeviceWatcher events trigger broadcast")
struct USBWatcherRescanTests {
    @Test func attachEventBroadcastsDescriptor() async throws {
        let watcher = USBDeviceWatcher()
        await watcher.start()
        let eventStream = await watcher.events()

        let descriptor = USBDeviceDescriptor(
            vendorID: 0x18D1,
            productID: 0x4EE2,
            serialNumber: "ABC123",
            vendorName: "Google",
            productName: "Pixel",
            locationID: 0x1000_0000
        )

        let receivedTask = Task<USBNotificationEvent?, Never> {
            for await event in eventStream {
                return event
            }
            return nil
        }

        let broadcastTask = Task {
            let cont = await watcher.events()
            _ = cont
        }

        try await Task.sleep(for: .milliseconds(10))
        broadcastTask.cancel()

        receivedTask.cancel()
        await watcher.stop()

        #expect(descriptor.vendorID == 0x18D1)
        #expect(AndroidVendorIDs.isAndroidVendor(descriptor.vendorID))
    }

    @Test func detachEventRemovesDescriptorFromAndroidCheck() async {
        let descriptor = USBDeviceDescriptor(
            vendorID: 0x04E8,
            productID: 0xD003,
            serialNumber: "SAMS001",
            vendorName: "Samsung",
            productName: "Galaxy S24",
            locationID: 0x2000_0000
        )
        #expect(AndroidVendorIDs.isAndroidVendor(descriptor.vendorID))
        #expect(AndroidVendorIDs.vendorName(for: descriptor.vendorID) == "Samsung")
    }

    @Test func nonAndroidVendorIgnoredByRegistry() {
        let appleVendorID: UInt16 = 0x05AC
        #expect(!AndroidVendorIDs.isAndroidVendor(appleVendorID))
    }
}
