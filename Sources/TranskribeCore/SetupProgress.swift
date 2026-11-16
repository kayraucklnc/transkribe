import Foundation

/// Where setup was when Transkribe last quit. macOS asks people to quit and reopen after allowing
/// call audio (Screen Recording), so reopening must land back on the same page instead of
/// starting setup over or skipping the permissions that are still left.
public struct SetupProgress: Codable, Equatable, Sendable {
    /// The onboarding page to reopen at (its index), or nil to start at the welcome.
    public var onboardingStep: Int?
    /// The permissions page opened after setup; it stays until the person presses Continue.
    public var reviewingPermissions: Bool

    public static let none = SetupProgress(onboardingStep: nil, reviewingPermissions: false)

    static let key = "setupProgress"

    public init(onboardingStep: Int?, reviewingPermissions: Bool) {
        self.onboardingStep = onboardingStep
        self.reviewingPermissions = reviewingPermissions
    }

    public static func load(from defaults: UserDefaults = .standard) -> SetupProgress {
        guard let data = defaults.data(forKey: key),
              let progress = try? JSONDecoder().decode(SetupProgress.self, from: data) else { return .none }
        return progress
    }

    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }

    /// Changes one part and saves it, leaving the rest as it was on disk.
    public static func update(in defaults: UserDefaults = .standard, _ change: (inout SetupProgress) -> Void) {
        var progress = load(from: defaults)
        change(&progress)
        progress.save(to: defaults)
    }

    /// After setup, the permissions page shows while recording can't work yet, and once open it
    /// keeps showing until the person moves on: allowing one permission and reopening doesn't skip the rest.
    public func showsPermissions(completedOnboarding: Bool, requiredGranted: Bool) -> Bool {
        completedOnboarding && (!requiredGranted || reviewingPermissions)
    }
}
