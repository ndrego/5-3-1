import Foundation

struct CompletedSet: Codable, Identifiable, Hashable {
    var id: UUID
    var weight: Double
    var targetReps: Int
    var actualReps: Int
    var isAMRAP: Bool
    var setType: SetType
    var averageHR: Double?  // Average heart rate during this set
    var hrSamples: [Double]?  // Per-sample HR readings during this set
    var estimatedRPE: Double?  // HR-based RPE estimate (1-10 scale)
    var restSeconds: Int?   // Custom rest duration after this set (nil = use default)

    init(
        weight: Double,
        targetReps: Int,
        actualReps: Int = 0,
        isAMRAP: Bool = false,
        setType: SetType = .main,
        averageHR: Double? = nil,
        restSeconds: Int? = nil
    ) {
        self.id = UUID()
        self.weight = weight
        self.targetReps = targetReps
        self.actualReps = actualReps
        self.isAMRAP = isAMRAP
        self.setType = setType
        self.averageHR = averageHR
        self.restSeconds = restSeconds
    }

    var isComplete: Bool {
        actualReps > 0
    }

    var exceededTarget: Bool {
        isAMRAP && actualReps > targetReps
    }
}

enum SetType: String, Codable, Hashable {
    case warmup
    case main
    case supplemental  // BBB, FSL, SSL sets
    case joker
    case accessory

    var displayName: String {
        switch self {
        case .warmup: return "Warm-up"
        case .main: return "Main"
        case .supplemental: return "Supplemental"
        case .joker: return "Joker"
        case .accessory: return "Accessory"
        }
    }
}
