import AppKit
import SwiftUI
import Testing
@testable import SplarkKit
@testable import SplarkUI

@MainActor @Suite struct PanelViewTests {
    func height(_ view: some View) throws -> Int {
        let png = try #require(Snapshot.png(view, scheme: .light, scale: 1))
        let rep = try #require(NSBitmapImageRep(data: png))
        #expect(rep.pixelsWide == 372)
        return rep.pixelsHigh
    }

    func panel(_ inbox: InboxStore, _ configure: (PanelModel) -> Void = { _ in }) -> PanelView {
        let model = PanelModel(actions: PreviewActions(), close: {}, openSlack: {}, openSettings: {})
        configure(model)
        return PanelView(inbox: inbox, status: nil, model: model, now: Fixtures.now, layout: .snapshot)
    }

    @Test func everyStateInTheGalleryRendersInBothSchemes() {
        for (name, view) in PanelGallery.states() {
            for scheme in [ColorScheme.light, .dark] { #expect(Snapshot.png(view, scheme: scheme) != nil, "\(name)") }
        }
    }

    @Test func anOpenRowAndOpenCommentsMakeThePanelTaller() throws {
        let inbox = Fixtures.inbox()
        let closed = try height(panel(inbox))
        #expect(try height(panel(inbox) { $0.toggle(inbox.items[0]) }) > closed + 100)
        #expect(try height(panel(inbox) { $0.commentsOpen = true }) > closed + 150)
    }

    @Test func theEmptyPanelIsShort() throws {
        #expect(try height(panel(Fixtures.emptyInbox())) < 160)
    }

    @Test func theHeadlineFollowsTheInbox() {
        #expect(Fixtures.inbox().summary.headline == "5 need you")
        #expect(Fixtures.emptyInbox().summary.headline == "All caught up")
    }
}
