import SwiftUI
import FreeDroidDomain
import FreeDroidUI

struct GalleryPresetFolder: Hashable {
    let label: String
    let path: RemotePath
}

let galleryPresetFolders: [GalleryPresetFolder] = [
    GalleryPresetFolder(label: "Camera", path: RemotePath(raw: "/sdcard/DCIM/Camera")),
    GalleryPresetFolder(label: "DCIM", path: RemotePath(raw: "/sdcard/DCIM")),
    GalleryPresetFolder(label: "Pictures", path: RemotePath(raw: "/sdcard/Pictures")),
    GalleryPresetFolder(label: "Screenshots", path: RemotePath(raw: "/sdcard/Pictures/Screenshots")),
    GalleryPresetFolder(label: "Downloads", path: RemotePath(raw: "/sdcard/Download")),
    GalleryPresetFolder(label: "Movies", path: RemotePath(raw: "/sdcard/Movies")),
    GalleryPresetFolder(label: "Music", path: RemotePath(raw: "/sdcard/Music")),
]

struct GalleryHeader: View {
    @Environment(\.theme) private var theme
    let viewModel: GalleryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text("Gallery")
                    .font(Typography.title)
                    .foregroundStyle(theme.colors.text0)

                Spacer()

                Menu {
                    ForEach(galleryPresetFolders, id: \.path.raw) { preset in
                        Button(preset.label) {
                            Task { await viewModel.setFolder(preset.path) }
                        }
                    }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Text(folderLabel(for: viewModel.currentFolder))
                            .font(Typography.bodyEmphasized)
                            .foregroundStyle(theme.colors.accent)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(theme.colors.accent)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.xs)

            HStack(spacing: Spacing.xs) {
                Text(viewModel.currentFolder.raw)
                    .font(Typography.monoCaption)
                    .foregroundStyle(theme.colors.text2)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if viewModel.photoCount > 0 || viewModel.videoCount > 0 {
                    Text("·")
                        .font(Typography.monoCaption)
                        .foregroundStyle(theme.colors.text3)
                    Text(countSummary)
                        .font(Typography.monoCaption)
                        .foregroundStyle(theme.colors.text2)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.md)

            Divider()
                .background(theme.colors.line)
        }
        .background(theme.colors.background0)
    }

    private var countSummary: String {
        let photos = viewModel.photoCount
        let videos = viewModel.videoCount
        var parts: [String] = []
        if photos > 0 {
            parts.append("\(photos) \(photos == 1 ? "photo" : "photos")")
        }
        if videos > 0 {
            parts.append("\(videos) \(videos == 1 ? "video" : "videos")")
        }
        return parts.joined(separator: " · ")
    }

    private func folderLabel(for path: RemotePath) -> String {
        if let preset = galleryPresetFolders.first(where: { $0.path == path }) {
            return preset.label
        }
        return path.raw.split(separator: "/").last.map(String.init) ?? path.raw
    }
}
