import Testing
@testable import FileBrowser

@Suite("FileBrowserPreviewableTypeTests")
struct FileBrowserPreviewableTypeTests {
    @Test func jpgIsPreviewable() {
        #expect(QuickLookEligibility.isPreviewable("photo.jpg"))
    }

    @Test func pngIsPreviewable() {
        #expect(QuickLookEligibility.isPreviewable("screenshot.png"))
    }

    @Test func mp4IsPreviewable() {
        #expect(QuickLookEligibility.isPreviewable("video.mp4"))
    }

    @Test func movIsPreviewable() {
        #expect(QuickLookEligibility.isPreviewable("clip.mov"))
    }

    @Test func pdfIsPreviewable() {
        #expect(QuickLookEligibility.isPreviewable("document.pdf"))
    }

    @Test func txtIsNotPreviewable() {
        #expect(!QuickLookEligibility.isPreviewable("readme.txt"))
    }

    @Test func binIsNotPreviewable() {
        #expect(!QuickLookEligibility.isPreviewable("data.bin"))
    }
}
