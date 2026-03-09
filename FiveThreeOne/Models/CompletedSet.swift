import Foundation

struct CompletedSet: Codable, Identifiable, Hashable {
    var id: UUID
    var weight: Double
    var targetReps: Int
    var actualReps: Int
    var isAMRAP: Bool
    var setType: SetType

    init(
        weight: Double,
        targetReps: Int,
        actualReps: Int = 0,
        isAMRAP: Bool = false,
        setType: SetType = .main
    ) {
        self.id = UUID()
        self.weight = weight
        self.targetReps = targetReps
        self.actualReps = actualReps
        self.isAMRAP = isAMRAP
        self.setType = setType
    }

    var isComplete: Bool {
        actualReps > 0
    }

    var exceededTarget: Bool {
        isAMRAP && actualReps > targetReps
    }
}

enum SetType: String, Codable, Hashable {
    case main
    case supplemental  // BBB, FSL, SSL sets
    case joker
    case accessory

    var displayName: String {
        switch self {
        case .main: return "Main"
        case .supplemental: return "Supplemental"
        case .joker: return "Joker"
        case .accessory: return "Accessory"
        }
    }
}
