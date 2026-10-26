// Trace — a tiny clipboard history for macOS.
// Copyright (C) 2026 SkryxDev
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Observation

enum PanelPosition: String, CaseIterable, Identifiable {
    case menuBar
    case mouse

    var id: Self { self }
}

/// User preferences, persisted in `UserDefaults`.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    static let historyLimits = [50, 100, 200, 500, 1000]

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored var onShortcutChange: ((Shortcut) -> Void)?
    @ObservationIgnored var onHistoryLimitChange: ((Int) -> Void)?
    @ObservationIgnored var onPausedChange: ((Bool) -> Void)?

    var shortcut: Shortcut {
        didSet {
            guard shortcut != oldValue else { return }
            if let data = try? JSONEncoder().encode(shortcut) { defaults.set(data, forKey: Keys.shortcut) }
            onShortcutChange?(shortcut)
        }
    }

    var autoPaste: Bool {
        didSet { defaults.set(autoPaste, forKey: Keys.autoPaste) }
    }

    var historyLimit: Int {
        didSet {
            defaults.set(historyLimit, forKey: Keys.historyLimit)
            onHistoryLimitChange?(historyLimit)
        }
    }

    var ignoreSensitive: Bool {
        didSet { defaults.set(ignoreSensitive, forKey: Keys.ignoreSensitive) }
    }

    /// Bundle identifiers of apps whose copies are never recorded.
    var excludedApps: [String] {
        didSet { defaults.set(excludedApps, forKey: Keys.excludedApps) }
    }

    var panelPosition: PanelPosition {
        didSet { defaults.set(panelPosition.rawValue, forKey: Keys.panelPosition) }
    }

    var isPaused: Bool {
        didSet {
            defaults.set(isPaused, forKey: Keys.isPaused)
            onPausedChange?(isPaused)
        }
    }

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.onboarding) }
    }

    private init() {
        defaults.register(defaults: [
            Keys.autoPaste: true,
            Keys.historyLimit: 200,
            Keys.ignoreSensitive: true,
        ])
        if let data = defaults.data(forKey: Keys.shortcut),
           let stored = try? JSONDecoder().decode(Shortcut.self, from: data) {
            shortcut = stored
        } else {
            shortcut = .default
        }
        autoPaste = defaults.bool(forKey: Keys.autoPaste)
        historyLimit = defaults.integer(forKey: Keys.historyLimit)
        ignoreSensitive = defaults.bool(forKey: Keys.ignoreSensitive)
        excludedApps = defaults.stringArray(forKey: Keys.excludedApps) ?? []
        panelPosition = PanelPosition(rawValue: defaults.string(forKey: Keys.panelPosition) ?? "") ?? .menuBar
        isPaused = defaults.bool(forKey: Keys.isPaused)
        hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarding)
    }

    private enum Keys {
        static let shortcut = "shortcut"
        static let autoPaste = "autoPaste"
        static let historyLimit = "historyLimit"
        static let ignoreSensitive = "ignoreSensitive"
        static let excludedApps = "excludedApps"
        static let panelPosition = "panelPosition"
        static let isPaused = "isPaused"
        static let onboarding = "hasCompletedOnboarding"
    }
}
