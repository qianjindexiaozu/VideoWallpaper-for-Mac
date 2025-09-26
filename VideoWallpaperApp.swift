import AppKit
import AVFoundation
import QuartzCore
import UniformTypeIdentifiers

// 播放层视图
final class WallpaperView: NSView {
    private let player = AVPlayer()
    private let playerLayer = AVPlayerLayer()

    init(url: URL) {
        super.init(frame: .zero)
        wantsLayer = true
        layer = CALayer()
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(playerLayer)

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.player.seek(to: .zero)
            self?.player.play()
        }

        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.isMuted = true
        player.play()
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }

    required init?(coder: NSCoder) { fatalError() }
}

// 桌面层窗口（在图标层下面、可点穿）
final class DesktopWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        setFrame(screen.frame, display: true)
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        ignoresMouseEvents = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    }
}

// 应用控制器：管理状态栏菜单、选择文件、铺放到各屏幕
final class AppController: NSObject {
    private var windows: [NSWindow] = []
    private var statusItem: NSStatusItem!

    private let fm = FileManager.default
    private let configURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/VideoWallpaper", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }()

    private struct Config: Codable { var videoPath: String }

    func start() {
        // 菜单栏图标
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let btn = statusItem.button {
            // 图标可能返回 nil 没关系，会显示空占位
            btn.image = NSImage(systemSymbolName: "play.rectangle.fill",
                                accessibilityDescription: "VideoWallpaper")
            btn.toolTip = "VideoWallpaper"
        }
        rebuildMenu()

        // 若已有配置，自动播放
        if let cfg = loadConfig(), fm.fileExists(atPath: cfg.videoPath) {
            applyVideo(URL(fileURLWithPath: cfg.videoPath))
        }

        // 监听屏幕变化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onScreenChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let chooseItem = NSMenuItem(title: "选择(choose) MP4…", action: #selector(selectVideo), keyEquivalent: "o")
        chooseItem.target = self
        menu.addItem(chooseItem)

        let pauseItem = NSMenuItem(title: "暂停(pause)/继续(continue)", action: #selector(togglePause), keyEquivalent: "p")
        pauseItem.target = self
        menu.addItem(pauseItem)

        if let cfg = loadConfig() {
            let short = (cfg.videoPath as NSString).abbreviatingWithTildeInPath
            let item = NSMenuItem(title: "当前(current)：\(short)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            let item = NSMenuItem(title: "未选择视频(nothing chosen)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        let aboutItem = NSMenuItem(title: "关于(about) VideoWallpaper", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "退出(quit)", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }


    @objc private func selectVideo() {
        let panel = NSOpenPanel()
        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [.movie]
        } else {
            panel.allowedFileTypes = ["mp4", "mov", "m4v"]
        }
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Confirm"
        if panel.runModal() == .OK, let url = panel.url {
            saveConfig(Config(videoPath: url.path))
            applyVideo(url)
            rebuildMenu()
        }
    }

    @objc private func togglePause() {
        if windows.isEmpty {
            if let cfg = loadConfig() {
                applyVideo(URL(fileURLWithPath: cfg.videoPath))
            }
        } else {
            clearWindows()
        }
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "VideoWallpaper"
        alert.informativeText = "https://github.com/qianjindexiaozu/VideoWallpaper-for-Mac"
        alert.runModal()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func onScreenChanged() {
        if let cfg = loadConfig(), fm.fileExists(atPath: cfg.videoPath) {
            applyVideo(URL(fileURLWithPath: cfg.videoPath))
        }
    }

    private func applyVideo(_ url: URL) {
        clearWindows()
        for screen in NSScreen.screens {
            let win = DesktopWindow(screen: screen)
            let view = WallpaperView(url: url)
            view.frame = win.contentLayoutRect
            win.contentView = view
            win.orderFrontRegardless()
            windows.append(win)
        }
    }

    private func clearWindows() {
        for w in windows { w.orderOut(nil) }
        windows.removeAll()
    }

    private func loadConfig() -> Config? {
        guard let data = try? Data(contentsOf: configURL) else { return nil }
        return try? JSONDecoder().decode(Config.self, from: data)
    }

    private func saveConfig(_ cfg: Config) {
        let dir = configURL.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(cfg) {
            try? data.write(to: configURL, options: .atomic)
        }
    }
}

// 入口：显式创建 NSApplication、绑定 delegate、运行事件循环
@main
final class AppMain: NSObject, NSApplicationDelegate {
    private let controller = AppController()

    static func main() {
        let app = NSApplication.shared
        let delegate = AppMain()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // 仅菜单栏
        app.run() // 关键：跑事件循环
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
    }
}
