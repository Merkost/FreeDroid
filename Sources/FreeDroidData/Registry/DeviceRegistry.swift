import Foundation
import FreeDroidDomain
import FreeDroidADB
import FreeDroidMTP

public actor DeviceRegistry {
    private var records: [DeviceID: DeviceRecord] = [:]
    private var consumers: [AsyncStream<[Device]>.Continuation] = []
    private let adbServer: ADBServer
    private let mtpRuntime: MTPRuntime
    private let mtpDiscovery: MTPDeviceDiscovery
    private let pinPreference: DevicePinPreference
    private let usbWatcher: USBDeviceWatcher
    private var usbSnapshot: [USBDeviceDescriptor] = []
    private var watcherTask: Task<Void, Never>?
    private var periodicTask: Task<Void, Never>?

    public init(
        adbServer: ADBServer,
        mtpRuntime: MTPRuntime,
        mtpDiscovery: MTPDeviceDiscovery,
        pinPreference: DevicePinPreference,
        usbWatcher: USBDeviceWatcher = USBDeviceWatcher()
    ) {
        self.adbServer = adbServer
        self.mtpRuntime = mtpRuntime
        self.mtpDiscovery = mtpDiscovery
        self.pinPreference = pinPreference
        self.usbWatcher = usbWatcher
    }

    public func start() async throws {
        try await adbServer.start()
        await mtpRuntime.start()
        await usbWatcher.start()
        startWatcherConsumer()
        startPeriodicRescan()
        try await rescan()
    }

    private func startWatcherConsumer() {
        watcherTask?.cancel()
        watcherTask = Task { [weak self] in
            guard let self else { return }
            let eventStream = await self.usbWatcher.events()
            for await event in eventStream {
                await self.handleUSBEvent(event)
            }
        }
    }

    private func startPeriodicRescan() {
        periodicTask?.cancel()
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                await self?.safeRescan()
            }
        }
    }

    private func handleUSBEvent(_ event: USBNotificationEvent) async {
        switch event {
        case .attached(let descriptor):
            if !usbSnapshot.contains(descriptor) {
                usbSnapshot.append(descriptor)
            }
        case .detached(let descriptor):
            usbSnapshot.removeAll { $0 == descriptor }
        }
        await safeRescan()
    }

    private func safeRescan() async {
        try? await rescan()
    }

    public func stop() async {
        watcherTask?.cancel()
        watcherTask = nil
        periodicTask?.cancel()
        periodicTask = nil
        await usbWatcher.stop()
    }

    public func rescan() async throws {
        var newRecords: [DeviceID: DeviceRecord] = [:]
        let adbDevices = (try? await adbServer.listDevices()) ?? []
        let mtpDevices = (try? await mtpDiscovery.detect()) ?? []
        let authorizedSerials = Set(adbDevices.filter { $0.state == .device }.map(\.serial))
        try await addAuthorizedADBRecords(
            adbDevices: adbDevices,
            mtpDevices: mtpDevices,
            into: &newRecords
        )
        await addMTPRecords(mtpDevices: mtpDevices, into: &newRecords)
        addUnauthorizedADBRecords(adbDevices: adbDevices, into: &newRecords)
        addChargingOnlyRecords(coveredSerials: Set(newRecords.keys.map(\.raw)),
                               authorizedSerials: authorizedSerials,
                               into: &newRecords)
        for (oldID, oldRecord) in records where newRecords[oldID] == nil {
            await oldRecord.transport?.close()
        }
        records = newRecords
        broadcast()
    }

    private func addAuthorizedADBRecords(
        adbDevices: [ADBDeviceListEntry],
        mtpDevices: [MTPRawDevice],
        into newRecords: inout [DeviceID: DeviceRecord]
    ) async throws {
        for adbEntry in adbDevices where adbEntry.state == .device {
            let identifier = adbEntry.serial
            let deviceID = DeviceID(raw: identifier)
            let pinned = await pinPreference.pinned(for: identifier)
            let kind = TransportSelector.select(
                adbAvailable: true,
                adbAuthorized: true,
                mtpAvailable: mtpDevices.contains { $0.identifier.contains(identifier) },
                pinned: pinned
            ) ?? .adb
            guard kind == .adb else { continue }
            let session = ADBSession(deviceID: deviceID, serial: identifier, server: adbServer)
            let deviceInfo = try await session.info
            let deviceRecord = Device(
                id: deviceID,
                displayName: adbEntry.model ?? deviceInfo.model,
                manufacturer: deviceInfo.manufacturer,
                model: deviceInfo.model,
                storageCapacityBytes: deviceInfo.storageCapacityBytes,
                storageFreeBytes: deviceInfo.storageFreeBytes,
                transport: .adb,
                connectionState: .ready
            )
            newRecords[deviceID] = DeviceRecord(device: deviceRecord, transport: session)
        }
    }

    private func addMTPRecords(
        mtpDevices: [MTPRawDevice],
        into newRecords: inout [DeviceID: DeviceRecord]
    ) async {
        for rawDevice in mtpDevices {
            let deviceID = DeviceID(raw: rawDevice.identifier)
            if newRecords[deviceID] != nil { continue }
            let session = MTPSession(deviceID: deviceID, raw: rawDevice)
            guard let deviceInfo = try? await session.info else { continue }
            let deviceRecord = Device(
                id: deviceID,
                displayName: rawDevice.productName ?? deviceInfo.model,
                manufacturer: deviceInfo.manufacturer,
                model: deviceInfo.model,
                storageCapacityBytes: deviceInfo.storageCapacityBytes,
                storageFreeBytes: deviceInfo.storageFreeBytes,
                transport: .mtp,
                connectionState: .ready
            )
            newRecords[deviceID] = DeviceRecord(device: deviceRecord, transport: session)
        }
    }

    private func addUnauthorizedADBRecords(
        adbDevices: [ADBDeviceListEntry],
        into newRecords: inout [DeviceID: DeviceRecord]
    ) {
        let unauthorizedEntries = adbDevices.filter {
            $0.state == .unauthorized || $0.state == .noPermissions
        }
        for adbEntry in unauthorizedEntries {
            let deviceID = DeviceID(raw: adbEntry.serial)
            if newRecords[deviceID] != nil { continue }
            let deviceRecord = Device(
                id: deviceID,
                displayName: adbEntry.model ?? adbEntry.serial,
                manufacturer: "",
                model: adbEntry.model ?? adbEntry.serial,
                storageCapacityBytes: nil,
                storageFreeBytes: nil,
                transport: .adb,
                connectionState: .pendingAuthorization
            )
            newRecords[deviceID] = DeviceRecord(device: deviceRecord, transport: nil)
        }
    }

    private func addChargingOnlyRecords(
        coveredSerials: Set<String>,
        authorizedSerials: Set<String>,
        into newRecords: inout [DeviceID: DeviceRecord]
    ) {
        for descriptor in usbSnapshot where AndroidVendorIDs.isAndroidVendor(descriptor.vendorID) {
            let serial = descriptor.serialNumber ?? "usb-\(descriptor.locationID)"
            let alreadyCovered = coveredSerials.contains(serial)
                || authorizedSerials.contains(where: { serial.contains($0) || $0.contains(serial) })
            if alreadyCovered { continue }
            let deviceID = DeviceID(raw: serial)
            if newRecords[deviceID] != nil { continue }
            let vendorLabel = AndroidVendorIDs.vendorName(for: descriptor.vendorID)
                ?? descriptor.vendorName
                ?? "Android"
            let productLabel = descriptor.productName ?? "Device"
            let deviceRecord = Device(
                id: deviceID,
                displayName: "\(vendorLabel) \(productLabel)",
                manufacturer: vendorLabel,
                model: productLabel,
                storageCapacityBytes: nil,
                storageFreeBytes: nil,
                transport: .adb,
                connectionState: .chargingOnly
            )
            newRecords[deviceID] = DeviceRecord(device: deviceRecord, transport: nil)
        }
    }

    public func observe() -> AsyncStream<[Device]> {
        AsyncStream { continuation in
            Task { await self.register(continuation) }
            continuation.onTermination = { _ in }
        }
    }

    public func device(_ identifier: DeviceID) async -> Device? {
        records[identifier]?.device
    }

    public func transport(for identifier: DeviceID) async -> (any Transport)? {
        records[identifier]?.transport
    }

    private func register(_ continuation: AsyncStream<[Device]>.Continuation) {
        consumers.append(continuation)
        continuation.yield(records.values.map(\.device))
    }

    private func broadcast() {
        let snapshot = records.values.map(\.device)
        for continuation in consumers {
            continuation.yield(snapshot)
        }
    }
}
