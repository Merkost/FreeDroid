import SwiftUI
import FreeDroidDomain
import FreeDroidUI

// swiftlint:disable:next type_body_length
public struct FileBrowserView: View {
    @Environment(\.theme) private var theme
    @Bindable var viewModel: FileBrowserViewModel
    @State private var renameTarget: RemoteEntry?
    @State private var newName: String = ""
    @State private var isCreatingFolder = false
    @State private var newFolderName: String = ""
    @State private var pendingDeletion = false
    @FocusState private var listFocused: Bool

    public init(viewModel: FileBrowserViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: 0) {
            mainColumn
            if let inspected = viewModel.inspectedEntry {
                FileInspectorView(viewModel: viewModel, entry: inspected)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .background(theme.colors.background0)
        .motion(.smooth, value: viewModel.inspectedEntry?.path)
        .focusable()
        .focused($listFocused)
        .onAppear { listFocused = true }
        .focusEffectDisabled()
        .task { await viewModel.reload() }
        .background(keyboardShortcuts)
        .sheet(item: $renameTarget) { entry in
            renameSheet(for: entry)
        }
        .sheet(isPresented: $isCreatingFolder) {
            newFolderSheet
        }
        .confirmationDialog(
            deletionPrompt,
            isPresented: $pendingDeletion,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await viewModel.deleteSelection() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var mainColumn: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                BreadcrumbBar(components: viewModel.breadcrumb) { destination in
                    Task { await viewModel.navigate(to: destination) }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)

                Divider().overlay(theme.colors.line)

                FileListHeader(sort: viewModel.sort, ascending: viewModel.sortAscending) { option in
                    viewModel.setSort(option)
                }

                contentArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .motion(.smooth, value: viewModel.isLoading)
                    .motion(.smooth, value: viewModel.entries.count)
            }

            if !viewModel.selection.isEmpty {
                CommandStrip(
                    selectionCount: viewModel.selection.count,
                    actions: [
                        CommandStripAction(label: "Delete", systemImage: "trash") {
                            pendingDeletion = true
                        },
                        CommandStripAction(label: "Clear", systemImage: "xmark.circle") {
                            viewModel.clearSelection()
                        }
                    ]
                )
                .padding(.bottom, Spacing.lg)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .motion(.smooth, value: viewModel.selection.count)
    }

    @ViewBuilder
    private var contentArea: some View {
        if viewModel.isLoading && viewModel.entries.isEmpty {
            FileListSkeleton(path: viewModel.path.raw, startedAt: viewModel.loadStartedAt)
        } else if viewModel.entries.isEmpty, let error = viewModel.lastError {
            errorContainer(error: error)
        } else if viewModel.entries.isEmpty {
            emptyContainer
        } else {
            list
        }
    }

    private func errorContainer(error: TransportError) -> some View {
        VStack {
            Spacer()
            FileBrowserErrorCard(error: error) {
                Task { await viewModel.reload() }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyContainer: some View {
        VStack {
            Spacer()
            EmptyState(
                icon: "folder",
                title: "Empty folder",
                message: "Drop files here to upload, or create a new folder to organize this device.",
                actionLabel: "New folder"
            ) {
                isCreatingFolder = true
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(viewModel.entries) { entry in
                        rowButton(for: entry)
                            .id(entry.path)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
            }
            .onChange(of: viewModel.focusedPath) { _, newValue in
                guard let target = newValue else { return }
                withAnimation(Motion.crisp.animation) {
                    proxy.scrollTo(target, anchor: .center)
                }
            }
        }
    }

    private func rowButton(for entry: RemoteEntry) -> some View {
        FileRowView(
            entry: entry,
            isSelected: viewModel.selection.contains(entry.path),
            isFocused: viewModel.focusedPath == entry.path
        )
        .onTapGesture { handleTap(entry: entry) }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                if entry.kind == .directory {
                    Task { await viewModel.navigate(to: entry.path) }
                }
            }
        )
        .contextMenu {
            if entry.kind == .directory {
                Button("Open") {
                    Task { await viewModel.navigate(to: entry.path) }
                }
            }
            Button("Rename") {
                renameTarget = entry
                newName = entry.name
            }
            Button("Delete", role: .destructive) {
                viewModel.selectOnly(entry.path)
                pendingDeletion = true
            }
        }
    }

    private func handleTap(entry: RemoteEntry) {
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.shift) {
            viewModel.extendSelection(to: entry.path)
            return
        }
        if modifiers.contains(.command) {
            viewModel.toggleSelection(entry.path)
            return
        }
        if entry.kind == .directory {
            viewModel.inspect(nil)
            Task { await viewModel.navigate(to: entry.path) }
            return
        }
        viewModel.selectOnly(entry.path)
        viewModel.inspect(entry)
    }

    private var deletionPrompt: String {
        let count = viewModel.selection.count
        return count == 1 ? "Delete 1 item?" : "Delete \(count) items?"
    }

    private var keyboardShortcuts: some View {
        VStack(spacing: 0) {
            Button("") { viewModel.setSort(.name) }
                .keyboardShortcut("1", modifiers: .command)
            Button("") { viewModel.setSort(.size) }
                .keyboardShortcut("2", modifiers: .command)
            Button("") { viewModel.setSort(.modified) }
                .keyboardShortcut("3", modifiers: .command)
            Button("") { viewModel.selectAll() }
                .keyboardShortcut("a", modifiers: .command)
            Button("") {
                guard !viewModel.selection.isEmpty else { return }
                pendingDeletion = true
            }
            .keyboardShortcut(.delete, modifiers: [])
            Button("") { viewModel.clearSelection() }
                .keyboardShortcut(.escape, modifiers: [])
            Button("") { Task { await viewModel.navigateUp() } }
                .keyboardShortcut(.delete, modifiers: .command)
            Button("") { viewModel.moveFocus(by: 1) }
                .keyboardShortcut(.downArrow, modifiers: [])
            Button("") { viewModel.moveFocus(by: -1) }
                .keyboardShortcut(.upArrow, modifiers: [])
            Button("") { viewModel.extendFocus(by: 1) }
                .keyboardShortcut(.downArrow, modifiers: .shift)
            Button("") { viewModel.extendFocus(by: -1) }
                .keyboardShortcut(.upArrow, modifiers: .shift)
            Button("") { Task { await viewModel.activateFocused() } }
                .keyboardShortcut(.return, modifiers: [])
        }
        .buttonStyle(.plain)
        .opacity(0)
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
