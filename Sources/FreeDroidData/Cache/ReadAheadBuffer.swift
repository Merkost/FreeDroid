import Foundation

public actor ReadAheadBuffer {
    private struct Segment {
        let offset: Int64
        let data: Data
    }

    private let capacity: Int
    private var segments: [Segment] = []

    public init(capacity: Int = 1024 * 1024) {
        self.capacity = capacity
    }

    public func store(offset: Int64, data: Data) async {
        segments.append(Segment(offset: offset, data: data))
        var total = segments.reduce(0) { $0 + $1.data.count }
        while total > capacity, !segments.isEmpty {
            let removed = segments.removeFirst()
            total -= removed.data.count
        }
    }

    public func read(offset: Int64, length: Int) async -> Data? {
        for segment in segments {
            let end = segment.offset + Int64(segment.data.count)
            if offset >= segment.offset && Int64(offset) + Int64(length) <= end {
                let local = Int(offset - segment.offset)
                return segment.data.subdata(in: local..<(local + length))
            }
        }
        return nil
    }

    public func clear() async {
        segments.removeAll()
    }
}
