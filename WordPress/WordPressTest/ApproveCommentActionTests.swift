import XCTest
@testable import WordPress

final class ApproveCommentActionTests: XCTestCase {
    private class TestableApproveComment: ApproveComment {
        let service: MockNotificationActionsService

        override var actionsService: NotificationActionsService? {
            return service
        }

        init(on: Bool, coreDataStack: CoreDataStack) {
            service = MockNotificationActionsService(managedObjectContext: coreDataStack.mainContext)
            super.init(on: on)
        }
    }

    private class MockNotificationActionsService: NotificationActionsService {
        var unapproveWasCalled: Bool = false
        var approveWasCalled: Bool = false

        override func unapproveCommentWithBlock(_ block: FormattableCommentContent, completion: ((Bool) -> Void)?) {
            unapproveWasCalled = true
            completion?(true)
        }

        override func approveCommentWithBlock(_ block: FormattableCommentContent, completion: ((Bool) -> Void)?) {
            approveWasCalled = true
            completion?(true)
        }
    }

    private var action: ApproveComment?
    private let utility = NotificationUtility()
    private var contextManager: ContextManagerMock!

    private struct Constants {
        static let initialStatus: Bool = false
    }

    override func setUp() {
        super.setUp()
        utility.setUp()
        contextManager = ContextManagerMock()
        action = TestableApproveComment(on: Constants.initialStatus, coreDataStack: contextManager)
        makeNetworkAvailable()
    }

    override func tearDown() {
        action = nil
        makeNetworkUnavailable()
        utility.tearDown()
        super.tearDown()
    }

    func testStatusPassedInInitialiserIsPreserved() {
        XCTAssertEqual(action?.on, Constants.initialStatus)
    }

    func testActionTitleIsExpected() {
        XCTAssertEqual(action?.actionTitle, ApproveComment.TitleStrings.approve)
    }

    func testSettingActionOnSetsExpectedTitle() {
        action?.on = true

        XCTAssertEqual(action?.actionTitle, ApproveComment.TitleStrings.unapprove)
    }

    func testSettingActionOffSetsExpectedTitle() {
        action?.on = false

        XCTAssertEqual(action?.actionTitle, ApproveComment.TitleStrings.approve)
    }

    func testExecuteCallsUnapproveWhenActionIsOn() throws {
        action?.on = true

        action?.execute(context: try utility.mockCommentContext())

        guard let mockService = action?.actionsService as? MockNotificationActionsService else {
            XCTFail()
            return
        }

        XCTAssertTrue(mockService.unapproveWasCalled)
    }

    func testExecuteUpdatesActionTitleWhenActionIsOn() throws {
        action?.on = true

        action?.execute(context: try utility.mockCommentContext())
        XCTAssertEqual(action?.actionTitle, ApproveComment.TitleStrings.approve)
    }

    func testExecuteCallsApproveWhenActionIsOff() throws {
        action?.on = false

        action?.execute(context: try utility.mockCommentContext())

        guard let mockService = action?.actionsService as? MockNotificationActionsService else {
            XCTFail()
            return
        }

        XCTAssertTrue(mockService.approveWasCalled)
    }

    func testExecuteUpdatesActionTitleWhenActionIsOff() throws {
        action?.on = false

        action?.execute(context: try utility.mockCommentContext())
        XCTAssertEqual(action?.actionTitle, ApproveComment.TitleStrings.unapprove)
    }
}
