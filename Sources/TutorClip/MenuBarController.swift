import AppKit

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private weak var coordinator: AppCoordinator?
    private let recentSessionsTag = 1001

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.button?.title = "TutorClip"
        buildMenu()
    }

    func refresh() {
        buildMenu()
    }

    private func buildMenu() {
        let language = coordinator?.settingsStore.settings.appLanguage ?? .chinese
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(NSMenuItem(title: language.text("截图", "Capture"), action: #selector(capture), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: language.text("历史", "History"), action: #selector(history), keyEquivalent: ""))
        let recentItem = NSMenuItem(title: language.text("最近记录", "Recent Sessions"), action: nil, keyEquivalent: "")
        recentItem.tag = recentSessionsTag
        menu.addItem(recentItem)
        menu.addItem(NSMenuItem(title: language.text("知识地图", "Knowledge Map"), action: #selector(knowledgeMap), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: language.text("设置", "Settings"), action: #selector(settings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: language.text("退出 TutorClip", "Quit TutorClip"), action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items {
            item.target = self
        }
        statusItem.menu = menu
    }

    @objc private func capture() {
        coordinator?.beginCapture()
    }

    @objc private func settings() {
        coordinator?.showSettings()
    }

    @objc private func knowledgeMap() {
        coordinator?.showKnowledgeMap()
    }

    @objc private func history() {
        coordinator?.showHistory()
    }

    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let session = sender.representedObject as? TutorSession else { return }
        coordinator?.openTutorWindow(session: session)
    }

    @objc private func quit() {
        coordinator?.quit()
    }

    private func recentSessionsMenu() -> NSMenu {
        let language = coordinator?.settingsStore.settings.appLanguage ?? .chinese
        let submenu = NSMenu()
        let sessions = coordinator?.recentSessions(limit: 5) ?? []
        if sessions.isEmpty {
            let item = NSMenuItem(title: language.text("暂无最近记录", "No Recent Sessions"), action: nil, keyEquivalent: "")
            item.isEnabled = false
            submenu.addItem(item)
            return submenu
        }
        for session in sessions {
            let item = NSMenuItem(title: session.title, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = session
            submenu.addItem(item)
        }
        return submenu
    }
}

extension MenuBarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        guard let item = menu.items.first(where: { $0.tag == recentSessionsTag }) else { return }
        item.submenu = recentSessionsMenu()
    }
}
