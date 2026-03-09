import Foundation

/// 5/3/1 program variants for assistance work
enum ProgramVariant: String, Codable, CaseIterable, Identifiable {
    case standard        // Main sets only, pick your own accessories
    case boringButBig    // BBB: 5x10 @ supplemental %
    case firstSetLast    // FSL: 3-5x5-8 @ first working set %
    case fivesPro        // 5s PRO: no AMRAP, all sets are 5 reps
    case bbbBeefcake     // BBB Beefcake: 5x10 @ FSL weight
    case ssl             // Second Set Last: 3-5x5 @ second working set %

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .boringButBig: return "Boring But Big (BBB)"
        case .firstSetLast: return "First Set Last (FSL)"
        case .fivesPro: return "5s PRO"
        case .bbbBeefcake: return "BBB Beefcake"
        case .ssl: return "Second Set Last (SSL)"
        }
    }

    var description: String {
        switch self {
        case .standard:
            return "Main 5/3/1 sets with AMRAP on the top set. Choose your own assistance."
        case .boringButBig:
            return "Main sets followed by 5x10 of the same lift at 50-60% of training max."
        case .firstSetLast:
            return "Main sets followed by 3-5 sets of 5-8 reps at the first working set percentage."
        case .fivesPro:
            return "All main sets are done for 5 reps (no AMRAP). Often paired with FSL or BBB."
        case .bbbBeefcake:
            return "5s PRO main work plus 5x10 at the first set percentage. Harder than standard BBB."
        case .ssl:
            return "Main sets followed by 3-5 sets of 5 reps at the second working set percentage."
        }
    }

    /// Whether the top set is AMRAP in this variant
    var hasAMRAP: Bool {
        switch self {
        case .fivesPro, .bbbBeefcake:
            return false
        default:
            return true
        }
    }

    /// Number of supplemental sets (after main work)
    var supplementalSets: Int {
        switch self {
        case .standard: return 0
        case .boringButBig, .bbbBeefcake: return 5
        case .firstSetLast: return 5
        case .ssl: return 5
        case .fivesPro: return 0  // 5s PRO is a main set modifier, not supplemental
        }
    }

    /// Target reps per supplemental set
    var supplementalReps: Int {
        switch self {
        case .boringButBig, .bbbBeefcake: return 10
        case .firstSetLast: return 5
        case .ssl: return 5
        default: return 0
        }
    }
}
