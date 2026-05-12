import FileProvider
import Foundation
import UniformTypeIdentifiers

public final class ProviderItem: NSObject, NSFileProviderItem {
    public let itemIdentifier: NSFileProviderItemIdentifier
    public let parentItemIdentifier: NSFileProviderItemIdentifier
    public let filename: String
    public let contentType: UTType
    public let capabilities: NSFileProviderItemCapabilities
    public let documentSize: NSNumber?
    public let creationDate: Date?
    public let contentModificationDate: Date?
    public let itemVersion: NSFileProviderItemVersion

    public static func root(displayName: String) -> ProviderItem {
        ProviderItem(
            itemIdentifier: .rootContainer,
            parentItemIdentifier: .rootContainer,
            filename: displayName,
            contentType: .folder,
            capabilities: [.allowsContentEnumerating, .allowsReading],
            documentSize: nil,
            creationDate: nil,
            contentModificationDate: nil,
            itemVersion: NSFileProviderItemVersion(
                contentVersion: Data("v1".utf8),
                metadataVersion: Data("v1".utf8)
            )
        )
    }

    public init(entry: RemoteEntry, parent: RemotePath) {
        let isDirectory = entry.kind == .directory
        self.itemIdentifier = NSFileProviderItemIdentifier(ItemIdentifier.encode(entry.path))
        self.parentItemIdentifier = parent.isRoot
            ? .rootContainer
            : NSFileProviderItemIdentifier(ItemIdentifier.encode(parent))
        self.filename = entry.name
        self.contentType = isDirectory ? .folder : Self.contentType(forName: entry.name)
        self.capabilities = isDirectory
            ? [.allowsContentEnumerating, .allowsReading, .allowsAddingSubItems,
               .allowsDeleting, .allowsRenaming]
            : [.allowsReading, .allowsWriting, .allowsDeleting, .allowsRenaming]
        self.documentSize = entry.sizeBytes.map { NSNumber(value: $0) }
        self.creationDate = nil
        self.contentModificationDate = entry.modifiedAt
        let mod = entry.modifiedAt?.timeIntervalSince1970 ?? 0
        let size = entry.sizeBytes ?? 0
        self.itemVersion = NSFileProviderItemVersion(
            contentVersion: Data("c:\(mod):\(size)".utf8),
            metadataVersion: Data("m:\(mod)".utf8)
        )
    }

    public init(
        itemIdentifier: NSFileProviderItemIdentifier,
        parentItemIdentifier: NSFileProviderItemIdentifier,
        filename: String,
        contentType: UTType,
        capabilities: NSFileProviderItemCapabilities,
        documentSize: NSNumber?,
        creationDate: Date?,
        contentModificationDate: Date?,
        itemVersion: NSFileProviderItemVersion
    ) {
        self.itemIdentifier = itemIdentifier
        self.parentItemIdentifier = parentItemIdentifier
        self.filename = filename
        self.contentType = contentType
        self.capabilities = capabilities
        self.documentSize = documentSize
        self.creationDate = creationDate
        self.contentModificationDate = contentModificationDate
        self.itemVersion = itemVersion
    }

    private static func contentType(forName name: String) -> UTType {
        let ext = (name as NSString).pathExtension
        if ext.isEmpty { return .data }
        return UTType(filenameExtension: ext) ?? .data
    }
}
