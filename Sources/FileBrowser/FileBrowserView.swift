import SwiftUI
import FreeDroidDomain
import FreeDroidUI

public struct FileBrowserView: View {
    @Environment(\.theme) private var theme
    @Bindable var viewModel: FileBrowserViewModel
    @State private var renameTarget: RemoteEntry?
    @State private var newName: String = ""
    @State private var isCreatingFolder = false
    @State private var newFolderName: String = ""

    public init(viewModel: FileBrowserViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                BreadcrumbBar(components: viewModel.breadcrumb) { path in
                    Task { await viewModel.navigate(to: path) }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)

                Divider().overlay(theme.colors.line)

                if viewModel.isLoading && viewModel.entries.isEmpty {
                    VStack {
                        Spacer()
                        Spinner(size: 24)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.entries.isEmpty {
                    EmptyState(
                        icon: "folder",
                        title: "Empty folder",
                        message: "Nothing here yet. Drag files in to upload.",
                        actionLabel: "New folder"
                    ) {
                        isCreatingFolder = true
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    list
                }
            }

            if !viewModel.selection.isEmpty {
                CommandStrip(
                    selectionCount: viewModel.selection.count,
                    actions: [
                        CommandStripAction(label: "Delete", systemImage: "trash") {
                            Task { await viewModel.deleteSelection() }
                        },
                        CommandStripAction(label: "Clear", systemImage: "xmark.circle") {
                            viewModel.clearSelection()
                        }
                    ]
                )
                .padding(.bottom, Spacing.lg)
            }
        }
        .task { await viewModel.reload() }
        .sheet(item: $renameTarget) { entry in
            renameSheet(for: entry)
        }
        .sheet(isPresented: $isCreatingFolder) {
            newFolderSheet
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(viewModel.entries) { entry in
                    FileRowView(entry: entry, isSelected: viewModel.selection.contains(entry.path))
                        .onTapGesture {
                            if entry.kind == .directory {
                                Task { await viewModel.navigate(to: entry.path) }
                            } else {
                                viewModel.toggleSelection(entry.path)
                            }
                        }
                        .contextMenu {
                            Button("Rename") {
                                renameTarget = entry
                                newName = entry.name
                            }
                            Button("Delete", role: .destructive) {
                                viewModel.selectOnly(entry.path)
                                Task { await viewModel.deleteSelection() }
                            }
                        }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
    }

    private func renameSheet(for entry: RemoteEntry) -> some View {
        FreeDroidUI.Sheet {
            Text("Rename").font(Typography.title)
            TextField("Name", text: $newName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { renameTarget = nil }
                Button("Rename") {
                    let target = entry
                    Task {
                        await viewModel.rename(target.path, to: newName)
                        renameTarget = nil
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.colors.accent)
                .disabled(newName.isEmpty)
            }
        }
        .padding()
    }

    private var newFolderSheet: some View {
        FreeDroidUI.Sheet {
            Text("New folder").font(Typography.title)
            TextField("Folder name", text: $newFolderName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") {
                    isCreatingFolder = false
                    newFolderName = ""
                }
                Button("Create") {
                    let name = newFolderName
                    Task {
                        await viewModel.createFolder(named: name)
                        isCreatingFolder = false
                        newFolderName = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.colors.accent)
                .disabled(newFolderName.isEmpty)
            }
        }
        .padding()
    }
}
