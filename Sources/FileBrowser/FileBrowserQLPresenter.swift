import SwiftUI
import AppKit
import Quartz

struct FileBrowserQLPresenter: NSViewRepresentable {
    @Binding var url: URL?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.attach(urlBinding: $url)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(url: url)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
        private var currentURL: URL?
        private var binding: Binding<URL?>?

        func attach(urlBinding: Binding<URL?>) {
            binding = urlBinding
        }

        func update(url: URL?) {
            currentURL = url
            if url == nil {
                QLPreviewPanel.shared()?.close()
            } else {
                guard let panel = QLPreviewPanel.shared() else { return }
                panel.dataSource = self
                panel.delegate = self
                panel.reloadData()
                panel.makeKeyAndOrderFront(nil)
            }
        }

        func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
            currentURL == nil ? 0 : 1
        }

        func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
            currentURL as NSURL?
        }
    }
}
