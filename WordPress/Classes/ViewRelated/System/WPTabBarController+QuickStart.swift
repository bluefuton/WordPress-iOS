private var spotlightView: QuickStartSpotlightView?
private var quickStartObserver: NSObject?

extension WPTabBarController {
    @objc func startWatchingQuickTours() {
        let observer = NotificationCenter.default.addObserver(forName: .QuickStartTourElementChangedNotification, object: nil, queue: nil) { [weak self] (notification) in
            spotlightView?.removeFromSuperview()
            spotlightView = nil

            let tabBarElements: [QuickStartTourElement] = [.readerTab, .notifications]

            guard let userInfo = notification.userInfo,
                let element = userInfo[QuickStartTourGuide.notificationElementKey] as? QuickStartTourElement,
                  tabBarElements.contains(element) else {
                    return
            }

            let newSpotlight = QuickStartSpotlightView()
            self?.view.addSubview(newSpotlight)

            guard let tabButton = self?.getTabButton(for: element) else {
                return
            }

            newSpotlight.translatesAutoresizingMaskIntoConstraints = false

            let newSpotlightCenterX = newSpotlight.centerXAnchor.constraint(equalTo: tabButton.centerXAnchor, constant: Constants.spotlightXOffset)
            let newSpotlightCenterY = newSpotlight.centerYAnchor.constraint(equalTo: tabButton.centerYAnchor, constant: Constants.spotlightYOffset)
            let newSpotlightWidth = newSpotlight.widthAnchor.constraint(equalToConstant: Constants.spotlightDiameter)
            let newSpotlightHeight = newSpotlight.heightAnchor.constraint(equalToConstant: Constants.spotlightDiameter)

            NSLayoutConstraint.activate([newSpotlightCenterX, newSpotlightCenterY, newSpotlightWidth, newSpotlightHeight])

            spotlightView = newSpotlight
        }

        quickStartObserver = observer as? NSObject
    }

    @objc func alertQuickStartThatReaderWasTapped() {
        QuickStartTourGuide.shared.visited(.readerTab)
    }

    @objc func alertQuickStartThatNotificationsWasTapped() {
        QuickStartTourGuide.shared.visited(.notifications)
    }

    @objc func alertQuickStartThatOtherTabWasTapped() {
        QuickStartTourGuide.shared.visited(.tabFlipped)
    }

    @objc func stopWatchingQuickTours() {
        NotificationCenter.default.removeObserver(quickStartObserver as Any)
        quickStartObserver = nil
    }

    private func getTabButton(for element: QuickStartTourElement) -> UIView? {
        guard let index = tabIndex(for: element) else {
            return nil
        }
        tabBar.layoutIfNeeded()
        var tabs = tabBar.subviews.compactMap { return $0 is UIControl ? $0 : nil }
        tabs.sort { $0.frame.origin.x < $1.frame.origin.x }
        return tabs[safe: index]
    }

    private func tabIndex(for element: QuickStartTourElement) -> Int? {
        switch element {
        case .readerTab:
            return Int(WPTab.reader.rawValue)
        case .notifications:
            return Int(WPTab.notifications.rawValue)
        default:
            return nil
        }
    }

    private enum Constants {
        static let spotlightDiameter: CGFloat = 40
        static let spotlightXOffset: CGFloat = 20
        static let spotlightYOffset: CGFloat = -10
    }
}
