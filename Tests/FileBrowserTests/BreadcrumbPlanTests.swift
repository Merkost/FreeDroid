import Testing
@testable import FileBrowser

@Suite("BreadcrumbPlan")
struct BreadcrumbPlanTests {
    @Test func wideEnoughShowsEverySegment() {
        let plan = BreadcrumbPlan.make(components: ["sdcard", "DCIM", "Camera"], availableWidth: 800)
        #expect(plan.items.count == 3)
        if case let .segment(last) = plan.items.last {
            #expect(last.isCurrent == true)
        } else {
            Issue.record("expected last item to be a segment")
        }
    }

    @Test func narrowCollapsesMiddleIntoEllipsis() {
        let plan = BreadcrumbPlan.make(
            components: ["sdcard", "Android", "data", "media", "Pictures"],
            availableWidth: 240
        )
        var sawEllipsis = false
        for item in plan.items {
            if case .ellipsis = item { sawEllipsis = true }
        }
        #expect(sawEllipsis)
    }

    @Test func lastSegmentRemainsCurrent() {
        let plan = BreadcrumbPlan.make(
            components: ["a", "b", "c", "d", "e", "f"],
            availableWidth: 300
        )
        let segments: [BreadcrumbPlan.Segment] = plan.items.compactMap { item in
            if case .segment(let segment) = item { return segment }
            return nil
        }
        #expect(segments.last?.name == "f")
        #expect(segments.last?.isCurrent == true)
    }
}
