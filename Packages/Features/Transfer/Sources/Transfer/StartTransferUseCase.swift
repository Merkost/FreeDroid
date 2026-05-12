import Foundation
import FreeDroidDomain

public struct StartTransferUseCase: Sendable {
    public let repository: any TransferRepository
    public let destinations: any TransferDestinationProvider

    public init(repository: any TransferRepository, destinations: any TransferDestinationProvider) {
        self.repository = repository
        self.destinations = destinations
    }

    public func callAsFunction(
        deviceID: DeviceID,
        deviceName: String,
        items: [RemotePath]
    ) -> AsyncThrowingStream<TransferProgress, Error> {
        let destination = destinations.destinationForDevice(deviceName)
        let job = TransferJob(
            deviceID: deviceID,
            direction: .toMac,
            items: items,
            destination: destination
        )
        return repository.enqueue(job)
    }
}
