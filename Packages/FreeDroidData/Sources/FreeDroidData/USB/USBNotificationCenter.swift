import Foundation
import IOKit
import IOKit.usb

public enum USBNotificationEvent: Sendable {
    case attached(USBDeviceDescriptor)
    case detached(USBDeviceDescriptor)
}

public final class USBNotificationCenter: @unchecked Sendable {
    private let stream: AsyncStream<USBNotificationEvent>
    private let continuation: AsyncStream<USBNotificationEvent>.Continuation
    nonisolated(unsafe) private let notificationPort: IONotificationPortRef

    public init() {
        var continuationOut: AsyncStream<USBNotificationEvent>.Continuation!
        self.stream = AsyncStream { continuation in continuationOut = continuation }
        self.continuation = continuationOut
        self.notificationPort = IONotificationPortCreate(kIOMainPortDefault)
    }

    public func start() {
        let runLoopSource = IONotificationPortGetRunLoopSource(notificationPort).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)

        let matchingDict = IOServiceMatching(kIOUSBDeviceClassName)
        var addedIterator: io_iterator_t = 0
        var removedIterator: io_iterator_t = 0

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        IOServiceAddMatchingNotification(
            notificationPort,
            kIOMatchedNotification,
            matchingDict,
            { selfPtr, iterator in
                let center = Unmanaged<USBNotificationCenter>.fromOpaque(selfPtr!).takeUnretainedValue()
                center.drainIterator(iterator, attached: true)
            },
            selfPtr,
            &addedIterator
        )
        drainIterator(addedIterator, attached: true)

        IOServiceAddMatchingNotification(
            notificationPort,
            kIOTerminatedNotification,
            IOServiceMatching(kIOUSBDeviceClassName),
            { selfPtr, iterator in
                let center = Unmanaged<USBNotificationCenter>.fromOpaque(selfPtr!).takeUnretainedValue()
                center.drainIterator(iterator, attached: false)
            },
            selfPtr,
            &removedIterator
        )
        drainIterator(removedIterator, attached: false)
    }

    public func events() -> AsyncStream<USBNotificationEvent> {
        stream
    }

    public func stop() {
        continuation.finish()
        IONotificationPortDestroy(notificationPort)
    }

    private func drainIterator(_ iterator: io_iterator_t, attached: Bool) {
        var service: io_object_t = IOIteratorNext(iterator)
        while service != 0 {
            if let descriptor = descriptor(for: service) {
                continuation.yield(attached ? .attached(descriptor) : .detached(descriptor))
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
    }

    private func descriptor(for service: io_object_t) -> USBDeviceDescriptor? {
        let vendor: UInt16? = numberProperty(service, key: kUSBVendorID as CFString)
        let product: UInt16? = numberProperty(service, key: kUSBProductID as CFString)
        guard let vendor, let product else { return nil }
        let serial = stringProperty(service, key: kUSBSerialNumberString as CFString)
        let vendorName = stringProperty(service, key: kUSBVendorString as CFString)
        let productName = stringProperty(service, key: kUSBProductString as CFString)
        let location: UInt32 = numberProperty(service, key: "locationID" as CFString) ?? 0
        return USBDeviceDescriptor(
            vendorID: vendor,
            productID: product,
            serialNumber: serial,
            vendorName: vendorName,
            productName: productName,
            locationID: location
        )
    }

    private func numberProperty<T: BinaryInteger>(_ service: io_object_t, key: CFString) -> T? {
        guard let cfValue = IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? NSNumber else {
            return nil
        }
        return T(exactly: cfValue.uint64Value)
    }

    private func stringProperty(_ service: io_object_t, key: CFString) -> String? {
        guard let cfValue = IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String else {
            return nil
        }
        return cfValue
    }
}
