import SwiftUI
import AppKit
import Quartz

public struct QuickLookPresenter: NSViewRepresentable {
    @Binding var url: URL?

    public init(url: Binding<URL?>) {
        self._url = url
    }

    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.attach(urlBinding: $url)
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(url: url)
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public final class Coordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
        private var currentURL: URL?
        private var binding: Binding<URL?>?

        func attach(urlBinding: Binding<URL?>) {
            self.binding = urlBinding
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

        public func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
            currentURL == nil ? 0 : 1
        }

        public func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
            currentURL as NSURL?
        }
    }
}
