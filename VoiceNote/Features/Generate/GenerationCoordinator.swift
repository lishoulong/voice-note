import Foundation
import SwiftUI
import UserNotifications
import UIKit

/// 「整理今日」的生成协调器:任务由它持有,不随等待页销毁 ——
/// 用户点「后台运行」离开后生成继续,完成时发本地通知 + 今天页出横幅承接。
/// 注意:切出 App 时 iOS 会挂起进程(Metal 推理暂停),回到 App 自动续跑;
/// 「后台」指的是 App 内切到别的页面。
@MainActor
@Observable
final class GenerationCoordinator {
    static let shared = GenerationCoordinator()

    private init() {
        // iOS 禁止后台提交 GPU 任务:退后台前暂停推理循环,回前台续跑,
        // 否则 Metal 命令被拒且后端进入错误态(kIOGPU...BackgroundExecutionNotPermitted)
        let nc = NotificationCenter.default
        nc.addObserver(forName: UIApplication.willResignActiveNotification,
                       object: nil, queue: .main) { _ in
            LlamaBridge.setGloballySuspended(true)
        }
        nc.addObserver(forName: UIApplication.didBecomeActiveNotification,
                       object: nil, queue: .main) { _ in
            LlamaBridge.setGloballySuspended(false)
        }
    }

    private(set) var isRunning = false
    /// 已完成但尚未查看的成稿(等待页在场则直接跳结果;不在场由横幅/通知承接)
    private(set) var completed: DiaryNote?

    // 实时生成进展(流式反馈:等待页显示已写字数与正在写的小节)
    private(set) var liveChars = 0
    private(set) var liveSection: String?

    @ObservationIgnored private var task: Task<Void, Never>?

    func start(entries: [Entry]) {
        guard !isRunning else { return }
        isRunning = true
        completed = nil
        liveChars = 0
        liveSection = nil
        requestPermissionIfNeeded()
        task = Task { [weak self] in
            let note = await DiaryGenerator.generate(from: entries, date: .now) { accumulated in
                Task { @MainActor [weak self] in self?.updateLive(accumulated) }
            }
            self?.finish(with: note ?? SampleData.makeTodayDraft())
        }
    }

    /// 从累积的 JSON 原文里提取可展示的进展:总字数 + 最近一个小节标题
    private func updateLive(_ raw: String) {
        liveChars = raw.count
        if let regex = try? NSRegularExpression(pattern: #""title"\s*:\s*"([^"]{1,20})""#),
           let last = regex.matches(in: raw, range: NSRange(raw.startIndex..., in: raw)).last,
           let r = Range(last.range(at: 1), in: raw) {
            let title = String(raw[r])
            // 第一个 title 是日记标题,后续的是小节标题;都值得展示
            liveSection = title
        }
    }

    /// 取走成稿(取走后横幅消失)
    func take() -> DiaryNote? {
        let n = completed
        completed = nil
        return n
    }

    private func finish(with note: DiaryNote) {
        isRunning = false
        completed = note
        AppLog.log("协调器: 生成结束, 来源=\(note.sourceLabel)")
        postDoneNotification()
    }

    // MARK: - 本地通知

    private func requestPermissionIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func postDoneNotification() {
        let content = UNMutableNotificationContent()
        content.title = "今日笔记已生成"
        content.body = "回到今天页查看成稿,确认后保存进日记。"
        content.sound = .default
        let req = UNNotificationRequest(identifier: "voicenote.generation.done",
                                        content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}

/// 让通知在 App 前台时也以横幅形式展示(默认前台不展示)
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
