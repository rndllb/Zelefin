import Foundation
import os
import SwiftUI

enum LibraryAlertSettings {
    static let enabledKey = "zelefin.alerts.enabled"
    static let quietHoursEnabledKey = "zelefin.alerts.quiet-hours.enabled"
    static let quietHoursStartKey = "zelefin.alerts.quiet-hours.start"
    static let quietHoursEndKey = "zelefin.alerts.quiet-hours.end"
    static let muteWhileOpenKey = "zelefin.alerts.mute-while-open"
    static let muteWhilePlayingKey = "zelefin.alerts.mute-while-playing"

    /// Minutes from midnight. Default 22:00.
    static let defaultQuietStartMinutes = 22 * 60
    /// Minutes from midnight. Default 07:00.
    static let defaultQuietEndMinutes = 7 * 60

    static var isEnabled: Bool {
        get { bool(for: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// When on, banners are suppressed between [quietHoursStartMinutes] and [quietHoursEndMinutes].
    static var quietHoursEnabled: Bool {
        get { bool(for: quietHoursEnabledKey, default: false) }
        set { UserDefaults.standard.set(newValue, forKey: quietHoursEnabledKey) }
    }

    static var quietHoursStartMinutes: Int {
        get { int(for: quietHoursStartKey, default: defaultQuietStartMinutes) }
        set { UserDefaults.standard.set(clampedMinutes(newValue), forKey: quietHoursStartKey) }
    }

    static var quietHoursEndMinutes: Int {
        get { int(for: quietHoursEndKey, default: defaultQuietEndMinutes) }
        set { UserDefaults.standard.set(clampedMinutes(newValue), forKey: quietHoursEndKey) }
    }

    /// When on, lock-screen banners are not shown while Zelefin is in the foreground.
    static var muteWhileOpen: Bool {
        get { bool(for: muteWhileOpenKey, default: true) }
        set { UserDefaults.standard.set(newValue, forKey: muteWhileOpenKey) }
    }

    /// When on, lock-screen banners are not shown while this device is playing in Zelefin.
    static var muteWhilePlaying: Bool {
        get { bool(for: muteWhilePlayingKey, default: true) }
        set { UserDefaults.standard.set(newValue, forKey: muteWhilePlayingKey) }
    }

    /// Set by the player while a session is on screen.
    /// The player view and player model each hold a presence token; the flag stays
    /// on until every holder has gone (dismiss, stop, or deinit).
    static var isPlaybackActive: Bool {
        get { playbackPresence.withLock { $0.active } }
        set { playbackPresence.withLock { $0.active = newValue } }
    }

    private struct PlaybackPresenceState: Sendable {
        var ids: Set<ObjectIdentifier> = []
        var active = false
    }

    private static let playbackPresence = OSAllocatedUnfairLock(initialState: PlaybackPresenceState())

    static func beginPlaybackPresence(_ owner: AnyObject) {
        let id = ObjectIdentifier(owner)
        playbackPresence.withLock { state in
            state.ids.insert(id)
            state.active = true
        }
    }

    static func endPlaybackPresence(_ owner: AnyObject) {
        let id = ObjectIdentifier(owner)
        playbackPresence.withLock { state in
            state.ids.remove(id)
            state.active = !state.ids.isEmpty
        }
    }

    /// Hour-and-minute picker bound to [quietHoursStartMinutes].
    static var quietHoursStartBinding: Binding<Date> {
        Binding(
            get: { date(fromMinutes: quietHoursStartMinutes) },
            set: { quietHoursStartMinutes = minutes(from: $0) }
        )
    }

    /// Hour-and-minute picker bound to [quietHoursEndMinutes].
    static var quietHoursEndBinding: Binding<Date> {
        Binding(
            get: { date(fromMinutes: quietHoursEndMinutes) },
            set: { quietHoursEndMinutes = minutes(from: $0) }
        )
    }

    static func date(fromMinutes minutes: Int, calendar: Calendar = .current) -> Date {
        let value = clampedMinutes(minutes)
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = value / 60
        components.minute = value % 60
        components.second = 0
        return calendar.date(from: components) ?? Date()
    }

    static func minutes(from date: Date, calendar: Calendar = .current) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }

    /// True when a banner should be held back right now (quiet hours / open / playing).
    static func shouldSuppressPresentation(appIsForeground: Bool) -> Bool {
        guard isEnabled else { return true }
        if muteWhilePlaying, isPlaybackActive { return true }
        if muteWhileOpen, appIsForeground { return true }
        if quietHoursEnabled, isInQuietHours(Date()) { return true }
        return false
    }

    static func isInQuietHours(_ date: Date, calendar: Calendar = .current) -> Bool {
        let minutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        return isMinuteInQuietHours(minutes, start: quietHoursStartMinutes, end: quietHoursEndMinutes)
    }

    /// Supports overnight ranges (e.g. 22:00 → 07:00).
    static func isMinuteInQuietHours(_ minutes: Int, start: Int, end: Int) -> Bool {
        let minute = clampedMinutes(minutes)
        let from = clampedMinutes(start)
        let to = clampedMinutes(end)
        if from == to { return true }
        if from < to { return minute >= from && minute < to }
        return minute >= from || minute < to
    }

    static func timeLabel(minutes: Int) -> String {
        let value = clampedMinutes(minutes)
        let hour = value / 60
        let minute = value % 60
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    private static func clampedMinutes(_ value: Int) -> Int {
        ((value % (24 * 60)) + (24 * 60)) % (24 * 60)
    }

    private static func bool(for key: String, default fallback: Bool = true) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return fallback }
        return UserDefaults.standard.bool(forKey: key)
    }

    private static func int(for key: String, default fallback: Int) -> Int {
        guard UserDefaults.standard.object(forKey: key) != nil else { return fallback }
        return UserDefaults.standard.integer(forKey: key)
    }
}

/// Holds mute-while-playing for one player screen or one player model.
final class PlaybackPresence {
    init() {
        LibraryAlertSettings.beginPlaybackPresence(self)
    }

    deinit {
        LibraryAlertSettings.endPlaybackPresence(self)
    }
}
