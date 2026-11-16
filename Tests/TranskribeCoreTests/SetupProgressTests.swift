import Foundation
import Testing
@testable import TranskribeCore

@Suite struct SetupProgressTests {
    @Test func startsFromTheBeginningWhenNothingWasSaved() {
        #expect(SetupProgress.load(from: Fixtures.temporaryDefaults()) == .none)
    }

    @Test func survivesAReopen() {
        let defaults = Fixtures.temporaryDefaults()
        let progress = SetupProgress(onboardingStep: 4, reviewingPermissions: true)
        progress.save(to: defaults)
        #expect(SetupProgress.load(from: defaults) == progress)
    }

    @Test func updateKeepsTheOtherPart() {
        let defaults = Fixtures.temporaryDefaults()
        SetupProgress.update(in: defaults) { $0.onboardingStep = 5 }
        SetupProgress.update(in: defaults) { $0.reviewingPermissions = true }
        #expect(SetupProgress.load(from: defaults) == SetupProgress(onboardingStep: 5, reviewingPermissions: true))
        SetupProgress.update(in: defaults) { $0.onboardingStep = nil }
        #expect(SetupProgress.load(from: defaults) == SetupProgress(onboardingStep: nil, reviewingPermissions: true))
    }

    @Test func unreadableDataStartsOver() {
        let defaults = Fixtures.temporaryDefaults()
        defaults.set(Data("not json".utf8), forKey: SetupProgress.key)
        #expect(SetupProgress.load(from: defaults) == .none)
    }

    @Test func permissionsPageStaysOpenAfterTheRequiredOnesAreAllowed() {
        let reviewing = SetupProgress(onboardingStep: nil, reviewingPermissions: true)
        #expect(reviewing.showsPermissions(completedOnboarding: true, requiredGranted: true))
        #expect(reviewing.showsPermissions(completedOnboarding: true, requiredGranted: false))
    }

    @Test func permissionsPageOnlyOpensByItselfWhenRecordingCantWork() {
        #expect(SetupProgress.none.showsPermissions(completedOnboarding: true, requiredGranted: false))
        #expect(!SetupProgress.none.showsPermissions(completedOnboarding: true, requiredGranted: true))
    }

    @Test func onboardingHandlesPermissionsItself() {
        let reviewing = SetupProgress(onboardingStep: 4, reviewingPermissions: true)
        #expect(!reviewing.showsPermissions(completedOnboarding: false, requiredGranted: false))
        #expect(!SetupProgress.none.showsPermissions(completedOnboarding: false, requiredGranted: false))
    }
}
