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

    public init(
        adbServer: ADBServer,
        mtpRuntime: MTPRuntime,
        mtpDiscovery: MTPDeviceDiscovery,
        pinPreference: DevicePinPreference
    ) {
        self.adbServer = adbServer
        self.mtpRuntime = mtpRuntime
        self.mtpDiscovery = mtpDiscovery
        self.pinPreference = pinPreference
    }

    public func start() async throws {
        try await adbServer.start()
        await mtpRuntime.start()
        try await rescan()
    }

    public func rescan() async throws {
        var newRecords: [DeviceID: DeviceRecord] = [:]

        let adbDevices = (try? await adbServer.listDevices()) ?? []
        let mtpDevices = (try? await mtpDiscovery.detect()) ?? []

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
            if kind == .adb {
                let session = ADBSession(deviceID: deviceID, serial: identifier, server: adbServer)
                let deviceInfo = try await session.info
                let device = Device(
                    id: deviceID,
                    displayName: adbEntry.model ?? deviceInfo.model,
                    manufacturer: deviceInfo.manufacturer,
                    model: deviceInfo.model,
                    storageCapacityBytes: deviceInfo.storageCapacityBytes,
                    storageFreeBytes: deviceInfo.storageFreeBytes,
                    transport: .adb
                )
                newRecords[deviceID] = DeviceRecord(device: device, transport: session)
            }
        }

        for rawDevice in mtpDevices {
            let deviceID = DeviceID(raw: rawDevice.identifier)
            if newRecords[deviceID] != nil { continue }
            let session = MTPSession(deviceID: deviceID, raw: rawDevice)
            let deviceInfo = try await session.info
            let device = Device(
                id: deviceID,
                displayName: rawDevice.productName ?? deviceInfo.model,
                manufacturer: deviceInfo.manufacturer,
                model: deviceInfo.model,
                storageCapacityBytes: deviceInfo.storageCapacityBytes,
                storageFreeBytes: deviceInfo.storageFreeBytes,
                transport: .mtp
            )
            newRecords[deviceID] = DeviceRecord(device: device, transport: session)
        }

        for (oldID, oldRecord) in records where newRecords[oldID] == nil {
            await oldRecord.transport.close()
        }
        records = newRecords
        broadcast()
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
