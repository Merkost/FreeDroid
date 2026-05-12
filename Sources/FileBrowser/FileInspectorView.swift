import SwiftUI
import AppKit
import FileProvider
import FreeDroidDomain
import FreeDroidUI

public struct FileInspectorView: View {
    @Environment(\.theme) private var theme
    @Bindable var viewModel: FileBrowserViewModel
    let entry: RemoteEntry

    public init(viewModel: FileBrowserViewModel, entry: RemoteEntry) {
        self.viewModel = viewModel
        self.entry = entry
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            previewBlock
            metadataBlock
            Spacer()
            actionButtons
        }
        .padding(Spacing.lg)
        .frame(width: 280)
        .background(theme.colors.background1.opacity(0.85))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(theme.colors.line)
                .frame(width: 1)
        }
    }

    private var previewBlock: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(theme.colors.background0)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(theme.colors.line, lineWidth: 1)
                )
            previewContent
                .padding(Spacing.md)
        }
        .frame(height: 220)
    }

    @ViewBuilder
    private var previewContent: some View {
        if viewModel.inspectorIsPreparing {
            Spinner(size: 24)
        } else if let url = viewModel.inspectorPreviewURL, let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        } else {
            VStack(spacing: Spacing.sm) {
                Image(systemName: FileIconResolver.symbol(for: entry))
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(theme.colors.text2)
                if !QuickLookEligibility.isInlinePreviewable(entry.name) {
                    Text("No inline preview")
                        .font(Typography.caption)
                        .foregroundStyle(theme.colors.text2)
                }
            }
        }
    }

    private var metadataBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(entry.name)
                .font(Typography.bodyEmphasized)
                .foregroundStyle(theme.colors.text0)
                .lineLimit(2)
                .truncationMode(.middle)
            if let size = entry.sizeBytes {
                Text(byteString(size))
                    .font(Typography.caption)
                    .foregroundStyle(theme.colors.text2)
            }
            if let date = entry.modifiedAt {
                Text(dateString(date))
                    .font(Typography.caption)
                    .foregroundStyle(theme.colors.text2)
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: Spacing.xs) {
            Button {
                Task {
                    if let url = await viewModel.openInspectedFile() {
                        NSWorkspace.shared.open(url)
                    }
                }
            } label: {
                Label("Open", systemImage: "arrow.up.right.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.colors.accent)

            Button {
                revealInFinder()
            } label: {
                Label("Show in Finder", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func revealInFinder() {
        guard let deviceID = viewModel.deviceID else { return }
        let entryPath = entry.path
        Task {
            let identifier = NSFileProviderDomainIdentifier(deviceID.raw)
            let domain = NSFileProviderDomain(identifier: identifier, displayName: "")
            if let manager = NSFileProviderManager(for: domain) {
                do {
                    let root = try await manager.getUserVisibleURL(for: .rootContainer)
                    let target = resolveProviderURL(root: root, entryPath: entryPath)
                    await MainActor.run {
                        NSWorkspace.shared.activateFileViewerSelecting([target])
                    }
                    return
                } catch {}
            }
            if let cached = viewModel.inspectorPreviewURL {
                await MainActor.run {
                    NSWorkspace.shared.activateFileViewerSelecting([cached])
                }
            }
        }
    }

    private func resolveProviderURL(root: URL, entryPath: RemotePath) -> URL {
        var url = root
        let components = entryPath.raw.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        for component in components {
            url = url.appendingPathComponent(component)
        }
        return url
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
