import Foundation
import UIKit
#if canImport(DeclaredAgeRange)
import DeclaredAgeRange
#endif
#if canImport(PermissionKit)
import PermissionKit
#endif

/// US app-store age laws (Texas SB 2420, Utah, Louisiana; docs/pro/COMPLIANCE.md, O9).
///
/// Before an account is made (the sign-in sheet) and before a purchase (the paywall), Snapreel
/// reads the age range the person, or their parent, declared to Apple, through the Declared Age
/// Range API, wherever Apple says the age laws apply (`isEligibleForAgeFeatures`):
/// - 18 and over: go ahead.
/// - Under 13: no account; the terms say 13 or older.
/// - 13 to 17: a parent or guardian has to approve, through Apple's parental-consent flow
///   (PermissionKit, sent to the parent in Messages). The answer arrives later, in
///   `startListening()`. Purchases by a minor also go through Apple's own approval (Ask to Buy),
///   which StoreKit handles as a pending purchase.
/// - Didn't share an age range: asked again next time; nothing is made or bought meanwhile.
///
/// Needs the `com.apple.developer.declared-age-range` entitlement (not in `Snapreel.entitlements`
/// yet: the App ID capability and App Store profile come first). Without it, before iOS 26.2,
/// outside the regulated regions, or when Apple can't answer, people go ahead as before.
@MainActor
enum AgeGate {
    enum Moment {
        case accountCreation
        case purchase
    }

    enum Outcome: Equatable {
        case allowed
        /// Under 13.
        case tooYoung
        /// 13 to 17: a parent or guardian has been asked and hasn't approved yet.
        case askedParent
        /// 13 to 17, but Apple couldn't ask a parent (no Family Sharing, for example).
        case needsParent
        /// Didn't share an age range where the law needs one.
        case declined
    }

    private static let approvedKey = "ageGate.parentApproved"

    #if DEBUG
    /// Debug screens show an outcome without asking Apple.
    static var debugOutcome: Outcome?
    #endif

    /// Whether `moment` may go ahead; shows Apple's age-range sheet (and asks a parent) when needed.
    static func check(_ moment: Moment) async -> Outcome {
        #if DEBUG
        if let debugOutcome { return debugOutcome }
        if AppEnvironment.shared.debugScreenID != nil { return .allowed }
        #endif
        #if canImport(DeclaredAgeRange) && canImport(PermissionKit)
        if #available(iOS 26.2, *), let presenter = ShareSheetPresenter.topViewController() {
            return await declaredAgeCheck(moment, presenter: presenter)
        }
        #endif
        return .allowed
    }

    /// What to tell the person, for anything but `.allowed`.
    static func message(for outcome: Outcome, moment: Moment) -> String? {
        switch outcome {
        case .allowed:
            return nil
        case .tooYoung:
            return "You need to be 13 or older to have a Snapreel account. You can still record and keep everything on this iPhone."
        case .askedParent:
            return moment == .purchase
                ? "We've asked your parent or guardian to approve your Snapreel account. Once they do, you can subscribe."
                : "We've asked your parent or guardian to approve your Snapreel account. Once they do, come back here to sign in."
        case .needsParent:
            return "Because you're under 18, a parent or guardian needs to approve your Snapreel account. Ask them to add you to their Family Sharing group, then try again."
        case .declined:
            return "Where you live, Snapreel needs your age range from Apple before you can make an account or subscribe. Share it when asked, or in Settings › your name › Personal Information › Age Range for Apps, then try again."
        }
    }

    /// Records the parent's answers as they arrive (approval or denial). Started at launch.
    static func startListening() {
        #if canImport(PermissionKit)
        if #available(iOS 26.2, *) {
            Task { @MainActor in
                for await response in AskCenter.shared.responses(for: SignificantAppUpdateTopic.self) {
                    if case .approval = response.choice.answer {
                        UserDefaults.standard.set(true, forKey: approvedKey)
                    } else {
                        UserDefaults.standard.set(false, forKey: approvedKey)
                    }
                }
            }
        }
        #endif
    }

    #if canImport(DeclaredAgeRange) && canImport(PermissionKit)
    @available(iOS 26.2, *)
    private static func declaredAgeCheck(_ moment: Moment, presenter: UIViewController) async -> Outcome {
        do {
            guard try await AgeRangeService.shared.isEligibleForAgeFeatures else { return .allowed }
        } catch {
            // Not available here (no entitlement yet, or no answer from Apple): as before.
            return .allowed
        }
        let response: AgeRangeService.Response
        do {
            response = try await AgeRangeService.shared.requestAgeRange(ageGates: 13, 18, in: presenter)
        } catch {
            return .allowed
        }
        guard case .sharing(let range) = response else { return .declined }
        if let lower = range.lowerBound, lower >= 18 { return .allowed }
        // No lower bound: below the lowest gate, so under 13.
        guard range.lowerBound != nil else { return .tooYoung }
        if UserDefaults.standard.bool(forKey: approvedKey) { return .allowed }
        return await askParent(in: presenter)
    }

    @available(iOS 26.2, *)
    private static func askParent(in presenter: UIViewController) async -> Outcome {
        let topic = SignificantAppUpdateTopic(description:
            "Snapreel would like to let your child make an account, to share recordings as links that other people can watch and comment on, and to subscribe to Snapreel Pro.")
        do {
            try await AskCenter.shared.ask(PermissionQuestion<SignificantAppUpdateTopic>(significantAppUpdateTopic: topic),
                                           in: presenter)
            return .askedParent
        } catch {
            return .needsParent
        }
    }
    #endif
}
