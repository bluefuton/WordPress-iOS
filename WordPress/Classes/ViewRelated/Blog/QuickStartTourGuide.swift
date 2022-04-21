import WordPressFlux
import Gridicons
import Foundation
import UIKit
import WordPressShared

@objc enum QuickStartTourOrigin: Int {
    case unknown
    case blogDetails
    case blogDashboard
}

open class QuickStartTourGuide: NSObject {
    var navigationSettings = QuickStartNavigationSettings()
    private var currentSuggestion: QuickStartTour?
    private var currentTourState: TourState?
    private var suggestionWorkItem: DispatchWorkItem?
    private weak var recentlyTouredBlog: Blog?
    private let noticeTag: Notice.Tag = "QuickStartTour"
    static let notificationElementKey = "QuickStartElementKey"
    static let notificationDescriptionKey = "QuickStartDescriptionKey"

    @objc var mustBeShownInBlogDetails: Bool {
        currentTourState?.tour.mustBeShownFromBlogDetails ?? false
    }

    /// A flag indicating if the user is currently going through a tour or not.
    private(set) var tourInProgress = false

    /// Represents the origin from which the current tour is triggered
    @objc var currentTourOrigin: QuickStartTourOrigin = .unknown

    @objc static let shared = QuickStartTourGuide()

    private override init() {}

    func setup(for blog: Blog, withCompletedSteps steps: [QuickStartTour] = []) {

        let createTour = QuickStartCreateTour()
        completed(tour: createTour, for: blog)

        steps.forEach { (tour) in
            completed(tour: tour, for: blog)
        }
        tourInProgress = false

        WPAnalytics.track(.quickStartStarted)

        NotificationCenter.default.post(name: .QuickStartTourElementChangedNotification,
                                        object: self,
                                        userInfo: [QuickStartTourGuide.notificationElementKey: QuickStartTourElement.setupQuickStart])
    }

    func setupWithDelay(for blog: Blog, withCompletedSteps steps: [QuickStartTour] = []) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.quickStartDelay) {
            self.setup(for: blog, withCompletedSteps: steps)
        }
    }

    @objc func remove(from blog: Blog) {
        blog.removeAllTours()
        endCurrentTour()
        NotificationCenter.default.post(name: .QuickStartTourElementChangedNotification, object: self)

        NotificationCenter.default.post(name: .QuickStartTourElementChangedNotification,
                                        object: self,
                                        userInfo: [QuickStartTourGuide.notificationElementKey: QuickStartTourElement.removeQuickStart])
    }

    @objc static func shouldShowChecklist(for blog: Blog) -> Bool {
        let list = QuickStartTourGuide.customizeListTours(for: blog) + QuickStartTourGuide.growListTours
        let checklistCompletedCount = countChecklistCompleted(in: list, for: blog)
        return checklistCompletedCount > 0
    }

    /// Provides a tour to suggest to the user
    ///
    /// - Parameter blog: The Blog for which to suggest a tour.
    /// - Returns: A QuickStartTour to suggest. `nil` if there are no appropriate tours.
    func tourToSuggest(for blog: Blog) -> QuickStartTour? {
        let completedTours: [QuickStartTourState] = blog.completedQuickStartTours ?? []
        let skippedTours: [QuickStartTourState] = blog.skippedQuickStartTours ?? []
        let unavailableTours = Array(Set(completedTours + skippedTours))
        let allTours = QuickStartTourGuide.customizeListTours(for: blog) + QuickStartTourGuide.growListTours

        guard isQuickStartEnabled(for: blog),
            recentlyTouredBlog == blog else {
                return nil
        }

        let unavailableIDs = unavailableTours.map { $0.tourID }
        let remainingTours = allTours.filter { !unavailableIDs.contains($0.key) }

        return remainingTours.first
    }

    func suggest(_ tour: QuickStartTour, for blog: Blog) {
        // swallow suggestions if already suggesting or a tour is in progress
        guard currentSuggestion == nil, currentTourState == nil else {
            return
        }
        currentSuggestion = tour

        let cancelTimer = { [weak self] (skipped: Bool) in
            self?.suggestionWorkItem?.cancel()
            self?.suggestionWorkItem = nil

            if skipped {
                self?.skipped(tour, for: blog)
            }
        }

        let newWorkItem = DispatchWorkItem { [weak self] in
            self?.dismissSuggestion()
            cancelTimer(true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.suggestionTimeout, execute: newWorkItem)
        suggestionWorkItem = newWorkItem

        let noticeStyle = QuickStartNoticeStyle(attributedMessage: nil)
        let notice = Notice(title: tour.title,
                            message: tour.description,
                            style: noticeStyle,
                            actionTitle: tour.suggestionYesText,
                            cancelTitle: tour.suggestionNoText,
                            tag: noticeTag) { [weak self] accepted in
                                self?.currentSuggestion = nil

                                if accepted {
                                    self?.prepare(tour: tour, for: blog)
                                    self?.begin()
                                    cancelTimer(false)
                                    WPAnalytics.track(.quickStartSuggestionButtonTapped, withProperties: ["type": "positive"])
                                } else {
                                    self?.skipped(tour, for: blog)
                                    cancelTimer(true)
                                    WPAnalytics.track(.quickStartSuggestionButtonTapped, withProperties: ["type": "negative"])
                                }
        }

        ActionDispatcher.dispatch(NoticeAction.post(notice))

        WPAnalytics.track(.quickStartSuggestionViewed)
    }

    /// Prepares to begin the specified tour.
    ///
    /// - Parameters:
    ///     - tour: the tour to prepare for running.
    ///     - blog: the blog in which the tour will take place.
    ///
    func prepare(tour: QuickStartTour, for blog: Blog) {
        endCurrentTour()
        dismissSuggestion()

        let adjustedTour = addSiteMenuWayPointIfNeeded(for: tour)

        switch adjustedTour {
        case let adjustedTour as QuickStartFollowTour:
            adjustedTour.setupReaderTab()
            fallthrough
        default:
            currentTourState = TourState(tour: adjustedTour, blog: blog, step: 0)
        }
    }

    private func addSiteMenuWayPointIfNeeded(for tour: QuickStartTour) -> QuickStartTour {

        if currentTourOrigin == .blogDashboard && tour.mustBeShownFromBlogDetails && !UIDevice.isPad() {
            var tourToAdjust = tour
            let siteMenuWaypoint = QuickStartSiteMenu.waypoint
            tourToAdjust.waypoints.insert(siteMenuWaypoint, at: 0)
            return tourToAdjust
        } else {
            return tour
        }
    }

    /// Begins the prepared tour.  Should only be called after `prepare(tour:for:)`.
    ///
    func begin() {
        guard let state = currentTourState,
            state.step == 0 else {

            return
        }

        tourInProgress = true
        showCurrentStep()
    }

    // Required for now because obj-c doesn't know about Quick Start tours
    @objc func completeSiteIconTour(forBlog blog: Blog) {
        complete(tour: QuickStartSiteIconTour(), silentlyForBlog: blog)
    }

    @objc func completeViewSiteTour(forBlog blog: Blog) {
        complete(tour: QuickStartViewTour(blog: blog), silentlyForBlog: blog)
    }

    @objc func completeSharingTour(forBlog blog: Blog) {
        complete(tour: QuickStartShareTour(), silentlyForBlog: blog)
    }

    /// Complete the specified tour without posting a notification.
    ///
    func complete(tour: QuickStartTour, silentlyForBlog blog: Blog) {
        complete(tour: tour, for: blog, postNotification: false)
    }

    func complete(tour: QuickStartTour, for blog: Blog, postNotification: Bool = true) {
        guard let tourCount = blog.quickStartTours?.count, tourCount > 0 else {
            // Tours haven't been set up yet or were skipped. No reason to continue.
            return
        }
        completed(tour: tour, for: blog, postNotification: postNotification)
    }

    // we have this because poor stupid ObjC doesn't know what the heck an optional is
    @objc func currentElementInt() -> Int {
        return currentWaypoint()?.element.rawValue ?? NSNotFound
    }

    @objc func isCurrentElement(_ testElement: QuickStartTourElement) -> Bool {
        guard let currentElement = currentElement() else {
            return false
        }
        return testElement == currentElement
    }

    func shouldSpotlight(_ element: QuickStartTourElement) -> Bool {
        return currentElement() == element
    }

    @objc func visited(_ element: QuickStartTourElement) {
        guard let currentElement = currentElement(),
            let tourState = currentTourState else {
            return
        }
        if element != currentElement {
            let blogDetailEvents: [QuickStartTourElement] = [.blogDetailNavigation, .checklist, .themes, .viewSite, .sharing, .siteMenu]
            let readerElements: [QuickStartTourElement] = [.readerTab, .readerSearch]

            if blogDetailEvents.contains(element) {
                endCurrentTour()
            } else if element == .tabFlipped, !readerElements.contains(currentElement) {
                endCurrentTour()
            }
            return
        }

        dismissCurrentNotice()

        guard let nextStep = getNextStep() else {

            if let taskCompleteDescription = tourState.tour.taskCompleteDescription {
                let noticeStyle = QuickStartNoticeStyle(attributedMessage: taskCompleteDescription)
                let notice = Notice(title: "", style: noticeStyle, tag: noticeTag)
                ActionDispatcher.dispatch(NoticeAction.post(notice))
            }

            completed(tour: tourState.tour, for: tourState.blog)
            currentTourState = nil

            // TODO: we could put a nice animation here
            return
        }

        if element == .siteMenu {
            showNextStepWithDelay(nextStep)
        } else {
            showNextStep(nextStep)
        }
    }

    private func showNextStep(_ nextStep: TourState) {
        currentTourState = nextStep
        showCurrentStep()
    }

    private func showNextStepWithDelay(_ nextStep: TourState) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.nextStepDelay) {
            self.currentTourState = nextStep
            self.showCurrentStep()
        }
    }

    func skipAll(for blog: Blog, whenSkipped: @escaping () -> Void) {
        let title = NSLocalizedString("Skip Quick Start", comment: "Title shown in alert to confirm skipping all quick start items")
        let message = NSLocalizedString("The quick start tour will guide you through building a basic site. Are you sure you want to skip? ",
                                            comment: "Description shown in alert to confirm skipping all quick start items")

        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)

        alertController.addCancelActionWithTitle(NSLocalizedString("Cancel", comment: "Button label when canceling alert in quick start"))

        let skipAction = alertController.addDefaultActionWithTitle(NSLocalizedString("Skip", comment: "Button label when skipping all quick start items")) { _ in
            let completedTours: [QuickStartTourState] = blog.completedQuickStartTours ?? []
            let completedIDs = completedTours.map { $0.tourID }

            for tour in QuickStartTourGuide.checklistTours(for: blog) {
                if !completedIDs.contains(tour.key) {
                    blog.completeTour(tour.key)
                }
            }

            whenSkipped()

            WPAnalytics.track(.quickStartChecklistSkippedAll)
        }
        alertController.preferredAction = skipAction

        WPTabBarController.sharedInstance()?.present(alertController, animated: true)
    }

    static func countChecklistCompleted(in list: [QuickStartTour], for blog: Blog) -> Int {
        let allChecklistTourIDs =  list.map { $0.key }
        let completedTourIDs = (blog.completedQuickStartTours ?? []).map { $0.tourID }
        let filteredIDs = allChecklistTourIDs.filter { completedTourIDs.contains($0) }
        return Set(filteredIDs).count
    }

    func countChecklistCompleted(in list: [QuickStartTour], for blog: Blog) -> Int {
        return QuickStartTourGuide.countChecklistCompleted(in: list, for: blog)
    }

    func endCurrentTour() {
        dismissCurrentNotice()
        currentTourState = nil
    }

    static func checklistTours(for blog: Blog) -> [QuickStartTour] {
        return [
            QuickStartCreateTour(),
            QuickStartViewTour(blog: blog),
            QuickStartThemeTour(),
            QuickStartShareTour(),
            QuickStartPublishTour(),
            QuickStartFollowTour()
        ]
    }

    static func customizeListTours(for blog: Blog) -> [QuickStartTour] {
        return [
            QuickStartCreateTour(),
            QuickStartSiteTitleTour(blog: blog),
            QuickStartSiteIconTour(),
            QuickStartEditHomepageTour(),
            QuickStartReviewPagesTour(),
            QuickStartViewTour(blog: blog)
        ]
    }

    static var growListTours: [QuickStartTour] {
        return [
            QuickStartShareTour(),
            QuickStartPublishTour(),
            QuickStartFollowTour(),
            QuickStartCheckStatsTour()
    // Temporarily disabled
    //        QuickStartExplorePlansTour()
        ]
    }
}

private extension QuickStartTourGuide {
    func isQuickStartEnabled(for blog: Blog) -> Bool {
        // there must be at least one completed tour for quick start to have been enabled
        guard let completedTours = blog.completedQuickStartTours else {
                return false
        }

        return completedTours.count > 0
    }

    func completed(tour: QuickStartTour, for blog: Blog, postNotification: Bool = true) {
        let completedTourIDs = (blog.completedQuickStartTours ?? []).map { $0.tourID }
        guard !completedTourIDs.contains(tour.key) else {
            return
        }

        blog.completeTour(tour.key)

        if postNotification {
            NotificationCenter.default.post(name: .QuickStartTourElementChangedNotification, object: self, userInfo: [QuickStartTourGuide.notificationElementKey: QuickStartTourElement.tourCompleted])

            // Create a site is completed automatically, we don't want to track
            if tour.analyticsKey != "create_site" {
                WPAnalytics.track(.quickStartTourCompleted, withProperties: ["task_name": tour.analyticsKey])
            }

            recentlyTouredBlog = blog
        } else {
            recentlyTouredBlog = nil
        }

        guard !(tour is QuickStartCongratulationsTour) else {
            WPAnalytics.track(.quickStartCongratulationsViewed)
            return
        }

        if allToursCompleted(for: blog) {
            WPAnalytics.track(.quickStartAllToursCompleted)
            grantCongratulationsAward(for: blog)
            tourInProgress = false
        } else {
            if let nextTour = tourToSuggest(for: blog) {
                PushNotificationsManager.shared.postNotification(for: nextTour)
            }
        }
    }

    /// Check if all the tours have been completed
    ///
    /// - Parameter blog: blog to check
    /// - Returns: boolean, true if all tours have been completed
    func allToursCompleted(for blog: Blog) -> Bool {
        let list = QuickStartTourGuide.customizeListTours(for: blog) + QuickStartTourGuide.growListTours
        return countChecklistCompleted(in: list, for: blog) >= list.count
    }

    /// Check if all the original (V1) tours have been completed
    ///
    /// - Parameter blog: a Blog to check
    /// - Returns: boolean, true if all the tours have been completed
    /// - Note: This method is needed for upgrade/migration to V2 and should not
    ///         be removed when the V2 feature flag is removed.
    func allOriginalToursCompleted(for blog: Blog) -> Bool {
        let list = QuickStartTourGuide.checklistTours(for: blog)
        return countChecklistCompleted(in: list, for: blog) >= list.count
    }

    func showCurrentStep() {
        guard let waypoint = currentWaypoint() else {
            return
        }

        if let state = currentTourState,
            state.tour.showWaypointNotices {
            showStepNotice(waypoint.description)
        }

        let userInfo: [String: Any] = [
            QuickStartTourGuide.notificationElementKey: waypoint.element,
            QuickStartTourGuide.notificationDescriptionKey: waypoint.description
            ]

        NotificationCenter.default.post(name: .QuickStartTourElementChangedNotification, object: self, userInfo: userInfo)
    }

    func showStepNotice(_ description: NSAttributedString) {
        let noticeStyle = QuickStartNoticeStyle(attributedMessage: description)
        let notice = Notice(title: "Test Quick Start Notice", style: noticeStyle, tag: noticeTag)
        ActionDispatcher.dispatch(NoticeAction.post(notice))
    }

    func currentWaypoint() -> QuickStartTour.WayPoint? {
        guard let state = currentTourState,
            state.step < state.tour.waypoints.count else {
                return nil
        }
        return state.tour.waypoints[state.step]
    }

    func currentElement() -> QuickStartTourElement? {
        return currentWaypoint()?.element
    }

    func dismissSuggestion() {
        guard currentSuggestion != nil else {
            return
        }

        tourInProgress = false
        currentSuggestion = nil
        ActionDispatcher.dispatch(NoticeAction.clearWithTag(noticeTag))
    }

    func getNextStep() -> TourState? {
        guard let tourState = currentTourState,
            tourState.step + 1 < tourState.tour.waypoints.count else {
                return nil
        }

        return TourState(tour: tourState.tour, blog: tourState.blog, step: tourState.step + 1)
    }

    func skipped(_ tour: QuickStartTour, for blog: Blog) {
        tourInProgress = false
        blog.skipTour(tour.key)
        recentlyTouredBlog = nil
    }

    // - TODO: Research if dispatching `NoticeAction.empty` is still necessary now that we use `.clearWithTag`.
    func dismissCurrentNotice() {
        ActionDispatcher.dispatch(NoticeAction.clearWithTag(noticeTag))
        ActionDispatcher.dispatch(NoticeAction.empty)
        NotificationCenter.default.post(name: .QuickStartTourElementChangedNotification, object: self, userInfo: [QuickStartTourGuide.notificationElementKey: QuickStartTourElement.noSuchElement])
    }

    private func grantCongratulationsAward(for blog: Blog) {
        let service = SiteManagementService(managedObjectContext: ContextManager.sharedInstance().mainContext)
        service.markQuickStartChecklistAsComplete(for: blog)
    }

    private struct Constants {
        static let maxSkippedTours = 3
        static let suggestionTimeout = 10.0
        static let quickStartDelay: DispatchTimeInterval = .milliseconds(500)
        static let nextStepDelay: DispatchTimeInterval = .milliseconds(1000)
    }
}

internal extension NSNotification.Name {
    static let QuickStartTourElementChangedNotification = NSNotification.Name(rawValue: "QuickStartTourElementChangedNotification")
}

private struct TourState {
    var tour: QuickStartTour
    var blog: Blog
    var step: Int
}
