import Foundation
import os.log
import FreeDroidDomain
import FreeDroidADB
import FreeDroidMTP

private let registryLogger = Logger(subsystem: "com.merkost.freedroid", category: "registry")

private struct USBVendorProduct: Hashable, Sendable {
    let vendorID: UInt16
    let productID: UInt16
}

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

    private var knownADBDescriptors: Set<USBVendorProduct> = []
    private var adbHintedModels: [String] = []
    private var missedRescans: [DeviceID: Int] = [:]
    private let maxMisses = 2
    private var lastBroadcastSnapshot: [Device] = []

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
                try? await Task.sleep(for: .seconds(15))
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
        try? await Task.sleep(for: .milliseconds(500))
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
        await addMTPRecords(
            mtpDevices: mtpDevices,
            adbSerials: authorizedSerials,
            usbSnapshot: usbSnapshot,
            into: &newRecords
        )
        addUnauthorizedADBRecords(adbDevices: adbDevices, into: &newRecords)
        let coveredVendorProducts = Set(
            newRecords.values.compactMap { record -> USBVendorProduct? in
                guard record.device.transport == .mtp else { return nil }
                return usbSnapshot.first { $0.serialNumber == record.device.id.raw }
                    .map { USBVendorProduct(vendorID: $0.vendorID, productID: $0.productID) }
            }
        ).union(knownADBDescriptors)
        addChargingOnlyRecords(coveredSerials: Set(newRecords.keys.map(\.raw)),
                               authorizedSerials: authorizedSerials,
                               coveredVendorProducts: coveredVendorProducts,
                               into: &newRecords)
        for (oldID, oldRecord) in records where newRecords[oldID] == nil {
            let misses = (missedRescans[oldID] ?? 0) + 1
            if misses <= maxMisses {
                missedRescans[oldID] = misses
                newRecords[oldID] = oldRecord
            } else {
                missedRescans.removeValue(forKey: oldID)
                await oldRecord.transport?.close()
            }
        }
        for newID in newRecords.keys {
            missedRescans.removeValue(forKey: newID)
        }
        records = newRecords
        broadcast()
    }

    private func addAuthorizedADBRecords(
        adbDevices: [ADBDeviceListEntry],
        mtpDevices: [MTPRawDevice],
        into newRecords: inout [DeviceID: DeviceRecord]
    ) async throws {
        var emittedModels: [String] = []
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
            let displayName = adbEntry.model ?? deviceInfo.model
            let deviceRecord = Device(
                id: deviceID,
                displayName: displayName,
                manufacturer: deviceInfo.manufacturer,
                model: deviceInfo.model,
                storageCapacityBytes: deviceInfo.storageCapacityBytes,
                storageFreeBytes: deviceInfo.storageFreeBytes,
                transport: .adb,
                connectionState: .ready
            )
            newRecords[deviceID] = DeviceRecord(device: deviceRecord, transport: session)
            recordADBDescriptors(forSerial: identifier)
            emittedModels.append(displayName)
            emittedModels.append(deviceInfo.model)
            emittedModels.append(deviceInfo.manufacturer)
        }
        adbHintedModels = emittedModels
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func nameOverlapsAnyADBHint(_ candidate: String) -> Bool {
        let candidateTokens = Self.tokens(in: candidate)
        guard !candidateTokens.isEmpty else { return false }
        for hint in adbHintedModels {
            let hintTokens = Self.tokens(in: hint)
            if !candidateTokens.intersection(hintTokens).isEmpty { return true }
        }
        return false
    }

    private static func tokens(in name: String) -> Set<String> {
        let lowered = name.lowercased()
        let separators = CharacterSet(charactersIn: " /_:()-")
        let parts = lowered.components(separatedBy: separators).filter { $0.count >= 3 }
        return Set(parts)
    }

    private func recordADBDescriptors(forSerial serial: String) {
        let exact = usbSnapshot.filter {
            $0.serialNumber == serial || $0.serialNumber.map { serial.contains($0) } == true
        }
        for descriptor in exact {
            knownADBDescriptors.insert(USBVendorProduct(vendorID: descriptor.vendorID, productID: descriptor.productID))
        }
        guard exact.isEmpty else { return }
        for descriptor in usbSnapshot where AndroidVendorIDs.isAndroidVendor(descriptor.vendorID) {
            knownADBDescriptors.insert(USBVendorProduct(vendorID: descriptor.vendorID, productID: descriptor.productID))
        }
    }

    private func addMTPRecords(
        mtpDevices: [MTPRawDevice],
        adbSerials: Set<String>,
        usbSnapshot: [USBDeviceDescriptor],
        into newRecords: inout [DeviceID: DeviceRecord]
    ) async {
        var skipped = 0
        var emitted = 0
        for rawDevice in mtpDevices {
            let deviceID = DeviceID(raw: rawDevice.identifier)
            if newRecords[deviceID] != nil { continue }
            let candidateVP = USBVendorProduct(vendorID: rawDevice.vendorID, productID: rawDevice.productID)
            if knownADBDescriptors.contains(candidateVP) {
                skipped += 1
                continue
            }
            let matchedDescriptor = usbSnapshot.first {
                $0.vendorID == rawDevice.vendorID && $0.productID == rawDevice.productID
            }
            if let descriptor = matchedDescriptor,
               let serial = descriptor.serialNumber,
               adbSerials.contains(serial) {
                skipped += 1
                continue
            }
            if let productName = rawDevice.productName,
               nameOverlapsAnyADBHint(productName) {
                skipped += 1
                continue
            }
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
            emitted += 1
        }
        registryLogger.debug("MTP scan: \(mtpDevices.count) discovered, \(skipped) owned by ADB, \(emitted) emitted")
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
        coveredVendorProducts: Set<USBVendorProduct>,
        into newRecords: inout [DeviceID: DeviceRecord]
    ) {
        for descriptor in usbSnapshot where AndroidVendorIDs.isAndroidVendor(descriptor.vendorID) {
            let serial = descriptor.serialNumber ?? "usb-\(descriptor.locationID)"
            let vendorProduct = USBVendorProduct(vendorID: descriptor.vendorID, productID: descriptor.productID)
            let alreadyCovered = coveredSerials.contains(serial)
                || authorizedSerials.contains(where: { serial.contains($0) || $0.contains(serial) })
                || coveredVendorProducts.contains(vendorProduct)
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

    fileprivate func register(_ continuation: AsyncStream<[Device]>.Continuation) {
        consumers.append(continuation)
        continuation.yield(sortedSnapshot())
    }

    fileprivate func broadcast() {
        let snapshot = sortedSnapshot()
        if snapshot == lastBroadcastSnapshot { return }
        lastBroadcastSnapshot = snapshot
        for continuation in consumers {
            continuation.yield(snapshot)
        }
    }

    private func sortedSnapshot() -> [Device] {
        records.values
            .map(\.device)
            .sorted { lhs, rhs in
                if lhs.connectionState == rhs.connectionState {
                    return lhs.id.raw < rhs.id.raw
                }
                return lhs.connectionState.sortRank < rhs.connectionState.sortRank
            }
    }
}

extension DeviceRegistry {
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
}
