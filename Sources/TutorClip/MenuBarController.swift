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
        buildApplicationMenu()
    }

    func refresh() {
        buildMenu()
        buildApplicationMenu()
    }

    private func buildApplicationMenu() {
        let language = coordinator?.settingsStore.settings.appLanguage ?? .chinese
        let mainMenu = NSMenu()

        let appItem = NSMenuItem(title: "TutorClip", action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: "TutorClip")
        let about = NSMenuItem(
            title: language.text("关于 TutorClip", "About TutorClip"),
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        about.target = NSApp
        appMenu.addItem(about)
        appMenu.addItem(.separator())
        let settings = NSMenuItem(title: language.text("设置…", "Settings…"), action: #selector(self.settings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        let hide = NSMenuItem(title: language.text("隐藏 TutorClip", "Hide TutorClip"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hide.target = NSApp
        appMenu.addItem(hide)
        let quit = NSMenuItem(title: language.text("退出 TutorClip", "Quit TutorClip"), action: #selector(self.quit), keyEquivalent: "q")
        quit.target = self
        appMenu.addItem(quit)
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem(title: language.text("编辑", "Edit"), action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: editItem.title)
        for item in ApplicationEditMenuItems.make(language: language) { editMenu.addItem(item) }
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    private func buildMenu() {
        let language = coordinator?.settingsStore.settings.appLanguage ?? .chinese
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: language.text("打开 TutorClip", "Open TutorClip"), action: #selector(openMain), keyEquivalent: ""))
        menu.delegate = self
        menu.addItem(NSMenuItem(title: language.text("截图", "Capture"), action: #selector(capture), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: language.text("历史", "History"), action: #selector(history), keyEquivalent: ""))
        let recentItem = NSMenuItem(title: language.text("最近记录", "Recent Sessions"), action: nil, keyEquivalent: "")
        recentItem.tag = recentSessionsTag
        menu.addItem(recentItem)
        menu.addItem(NSMenuItem(title: language.text("知识地图", "Knowledge Map"), action: #selector(knowledgeMap), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: language.text("帮助与设置", "Help & Settings"), action: #selector(settings), keyEquivalent: ","))
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

    @objc private func openMain() {
        coordinator?.showMainWindow()
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

enum ApplicationEditMenuItems {
    static func make(language: AppLanguage) -> [NSMenuItem] {
        let undo = NSMenuItem(title: language.text("撤销", "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: language.text("重做", "Redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        let cut = NSMenuItem(title: language.text("剪切", "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        let copy = NSMenuItem(title: language.text("复制", "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        let paste = NSMenuItem(title: language.text("粘贴", "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let selectAll = NSMenuItem(title: language.text("全选", "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return [undo, redo, .separator(), cut, copy, paste, .separator(), selectAll]
    }
}

extension MenuBarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        guard let item = menu.items.first(where: { $0.tag == recentSessionsTag }) else { return }
        item.submenu = recentSessionsMenu()
    }
}
