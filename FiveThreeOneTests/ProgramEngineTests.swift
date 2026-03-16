import XCTest
@testable import FiveThreeOne

final class ProgramEngineTests: XCTestCase {

    // MARK: - Week Labels

    func testWeekLabels() {
        XCTAssertEqual(ProgramEngine.weekLabel(1), "5/5/5+")
        XCTAssertEqual(ProgramEngine.weekLabel(2), "3/3/3+")
        XCTAssertEqual(ProgramEngine.weekLabel(3), "5/3/1+")
        XCTAssertEqual(ProgramEngine.weekLabel(4), "Deload")
        XCTAssertEqual(ProgramEngine.weekLabel(5), "TM Test")
        XCTAssertEqual(ProgramEngine.weekLabel(6), "1RM Test")
    }

    // MARK: - Estimated 1RM

    func testEstimated1RM_Epley() {
        let e1rm = ProgramEngine.estimated1RM(weight: 200, reps: 5)
        // Epley: 200 * (1 + 5/30) = 200 * 1.1667 = 233.33
        XCTAssertEqual(e1rm, 200 * (1 + 5.0 / 30.0), accuracy: 0.01)
    }

    func testEstimated1RM_SingleRep() {
        // 1 rep should return weight itself
        XCTAssertEqual(ProgramEngine.estimated1RM(weight: 315, reps: 1), 315)
    }

    func testEstimated1RM_ZeroWeight() {
        XCTAssertEqual(ProgramEngine.estimated1RM(weight: 0, reps: 5), 0)
    }

    // MARK: - Warmup Sets

    func testWarmupSets_Default() {
        let sets = ProgramEngine.warmupSets(trainingMax: 200, roundTo: 5.0)
        XCTAssertEqual(sets.count, 3)

        // 40% of 200 = 80, 50% = 100, 60% = 120
        XCTAssertEqual(sets[0].weight, 80)
        XCTAssertEqual(sets[0].reps, 5)
        XCTAssertEqual(sets[0].setType, .warmup)
        XCTAssertFalse(sets[0].isAMRAP)

        XCTAssertEqual(sets[1].weight, 100)
        XCTAssertEqual(sets[1].reps, 5)

        XCTAssertEqual(sets[2].weight, 120)
        XCTAssertEqual(sets[2].reps, 3)
    }

    func testWarmupSets_CustomScheme() {
        let scheme: [(percentage: Double, reps: Int)] = [(0.30, 5), (0.50, 3)]
        let sets = ProgramEngine.warmupSets(trainingMax: 200, scheme: scheme, roundTo: 5.0)
        XCTAssertEqual(sets.count, 2)
        XCTAssertEqual(sets[0].weight, 60)  // 30% of 200
        XCTAssertEqual(sets[0].reps, 5)
        XCTAssertEqual(sets[1].weight, 100) // 50% of 200
        XCTAssertEqual(sets[1].reps, 3)
    }

    func testWarmupSets_Rounding() {
        // 40% of 315 = 126, rounds to 125
        let sets = ProgramEngine.warmupSets(trainingMax: 315, roundTo: 5.0)
        XCTAssertEqual(sets[0].weight, 125)
    }

    // MARK: - Main Sets: Standard Variant

    func testMainSets_Standard_Week1() {
        let sets = ProgramEngine.mainSets(trainingMax: 200, week: 1, variant: .standard, roundTo: 5.0)
        XCTAssertEqual(sets.count, 3)

        // 65% = 130, 75% = 150, 85% = 170
        XCTAssertEqual(sets[0].weight, 130)
        XCTAssertEqual(sets[0].reps, 5)
        XCTAssertFalse(sets[0].isAMRAP)

        XCTAssertEqual(sets[1].weight, 150)
        XCTAssertEqual(sets[1].reps, 5)
        XCTAssertFalse(sets[1].isAMRAP)

        XCTAssertEqual(sets[2].weight, 170)
        XCTAssertEqual(sets[2].reps, 5)
        XCTAssertTrue(sets[2].isAMRAP) // Last set is AMRAP for standard
    }

    func testMainSets_Standard_Week2() {
        let sets = ProgramEngine.mainSets(trainingMax: 200, week: 2, variant: .standard, roundTo: 5.0)
        XCTAssertEqual(sets.count, 3)
        // 70% = 140, 80% = 160, 90% = 180
        XCTAssertEqual(sets[0].weight, 140)
        XCTAssertEqual(sets[0].reps, 3)
        XCTAssertEqual(sets[1].weight, 160)
        XCTAssertEqual(sets[1].reps, 3)
        XCTAssertEqual(sets[2].weight, 180)
        XCTAssertEqual(sets[2].reps, 3)
        XCTAssertTrue(sets[2].isAMRAP)
    }

    func testMainSets_Standard_Week3() {
        let sets = ProgramEngine.mainSets(trainingMax: 200, week: 3, variant: .standard, roundTo: 5.0)
        XCTAssertEqual(sets.count, 3)
        // 75% = 150, 85% = 170, 95% = 190
        XCTAssertEqual(sets[0].weight, 150)
        XCTAssertEqual(sets[0].reps, 5)
        XCTAssertEqual(sets[1].weight, 170)
        XCTAssertEqual(sets[1].reps, 3)
        XCTAssertEqual(sets[2].weight, 190)
        XCTAssertEqual(sets[2].reps, 1)
        XCTAssertTrue(sets[2].isAMRAP)
    }

    func testMainSets_Standard_Week4_Deload() {
        let sets = ProgramEngine.mainSets(trainingMax: 200, week: 4, variant: .standard, roundTo: 5.0)
        XCTAssertEqual(sets.count, 3)
        // 40% = 80, 50% = 100, 60% = 120
        XCTAssertEqual(sets[0].weight, 80)
        XCTAssertEqual(sets[1].weight, 100)
        XCTAssertEqual(sets[2].weight, 120)
        // No AMRAP on deload
        for set in sets {
            XCTAssertFalse(set.isAMRAP)
            XCTAssertEqual(set.reps, 5)
        }
    }

    func testMainSets_Standard_Week5_TMTest() {
        let sets = ProgramEngine.mainSets(trainingMax: 200, week: 5, variant: .standard, roundTo: 5.0)
        XCTAssertEqual(sets.count, 4)
        // 70% = 140, 80% = 160, 90% = 180, 100% = 200
        XCTAssertEqual(sets[0].weight, 140)
        XCTAssertEqual(sets[0].reps, 5)
        XCTAssertEqual(sets[1].weight, 160)
        XCTAssertEqual(sets[1].reps, 3)
        XCTAssertEqual(sets[2].weight, 180)
        XCTAssertEqual(sets[2].reps, 1)
        XCTAssertEqual(sets[3].weight, 200)
        XCTAssertEqual(sets[3].reps, 3)
        XCTAssertTrue(sets[3].isAMRAP)
    }

    func testMainSets_Standard_Week6_1RMTest() {
        let sets = ProgramEngine.mainSets(trainingMax: 200, week: 6, variant: .standard, roundTo: 5.0)
        XCTAssertEqual(sets.count, 6)
        // 50%=100, 60%=120, 70%=140, 80%=160, 90%=180, 100%=200
        XCTAssertEqual(sets[0].weight, 100)
        XCTAssertEqual(sets[5].weight, 200)
        XCTAssertTrue(sets[5].isAMRAP)
        // Only last set is AMRAP
        for i in 0..<5 {
            XCTAssertFalse(sets[i].isAMRAP)
        }
    }

    // MARK: - Main Sets: 5s PRO Variant

    func testMainSets_FivesPro_Week1() {
        let sets = ProgramEngine.mainSets(trainingMax: 200, week: 1, variant: .fivesPro, roundTo: 5.0)
        XCTAssertEqual(sets.count, 3)
        // Same weights as standard but all 5 reps, no AMRAP
        XCTAssertEqual(sets[0].weight, 130)
        XCTAssertEqual(sets[1].weight, 150)
        XCTAssertEqual(sets[2].weight, 170)
        for set in sets {
            XCTAssertEqual(set.reps, 5)
            XCTAssertFalse(set.isAMRAP)
        }
    }

    func testMainSets_FivesPro_Week3() {
        let sets = ProgramEngine.mainSets(trainingMax: 200, week: 3, variant: .fivesPro, roundTo: 5.0)
        // 5s PRO overrides reps to 5 for weeks 1-3
        for set in sets {
            XCTAssertEqual(set.reps, 5)
            XCTAssertFalse(set.isAMRAP)
        }
    }

    // MARK: - Main Sets: BBB Beefcake Variant

    func testMainSets_BBBBeefcake_Week1() {
        let sets = ProgramEngine.mainSets(trainingMax: 200, week: 1, variant: .bbbBeefcake, roundTo: 5.0)
        // Beefcake: all 5 reps, no AMRAP
        for set in sets {
            XCTAssertEqual(set.reps, 5)
            XCTAssertFalse(set.isAMRAP)
        }
    }

    // MARK: - Supplemental Sets

    func testSupplementalSets_Standard_ReturnsEmpty() {
        let sets = ProgramEngine.supplementalSets(trainingMax: 200, week: 1, variant: .standard, roundTo: 5.0)
        XCTAssertTrue(sets.isEmpty)
    }

    func testSupplementalSets_FivesPro_ReturnsEmpty() {
        let sets = ProgramEngine.supplementalSets(trainingMax: 200, week: 1, variant: .fivesPro, roundTo: 5.0)
        XCTAssertTrue(sets.isEmpty)
    }

    func testSupplementalSets_BBB_Week1() {
        let sets = ProgramEngine.supplementalSets(trainingMax: 200, week: 1, variant: .boringButBig, roundTo: 5.0)
        XCTAssertEqual(sets.count, 5)
        // BBB: 50% of TM = 100
        for set in sets {
            XCTAssertEqual(set.weight, 100)
            XCTAssertEqual(set.reps, 10)
            XCTAssertEqual(set.setType, .supplemental)
            XCTAssertFalse(set.isAMRAP)
        }
    }

    func testSupplementalSets_FSL_Week1() {
        let sets = ProgramEngine.supplementalSets(trainingMax: 200, week: 1, variant: .firstSetLast, roundTo: 5.0)
        XCTAssertEqual(sets.count, 5)
        // FSL: first set percentage = 65% of 200 = 130
        for set in sets {
            XCTAssertEqual(set.weight, 130)
            XCTAssertEqual(set.reps, 5)
            XCTAssertEqual(set.setType, .supplemental)
        }
    }

    func testSupplementalSets_SSL_Week2() {
        let sets = ProgramEngine.supplementalSets(trainingMax: 200, week: 2, variant: .ssl, roundTo: 5.0)
        XCTAssertEqual(sets.count, 5)
        // SSL: second set percentage, week 2 = 80% = 160
        for set in sets {
            XCTAssertEqual(set.weight, 160)
            XCTAssertEqual(set.reps, 5)
        }
    }

    func testSupplementalSets_BBBBeefcake_Week1() {
        let sets = ProgramEngine.supplementalSets(trainingMax: 200, week: 1, variant: .bbbBeefcake, roundTo: 5.0)
        XCTAssertEqual(sets.count, 5)
        // Beefcake: first set percentage = 65% = 130, 10 reps
        for set in sets {
            XCTAssertEqual(set.weight, 130)
            XCTAssertEqual(set.reps, 10)
        }
    }

    func testSupplementalSets_Deload_ReturnsEmpty() {
        // No supplemental on deload/test weeks
        for variant in ProgramVariant.allCases {
            let sets = ProgramEngine.supplementalSets(trainingMax: 200, week: 4, variant: variant, roundTo: 5.0)
            XCTAssertTrue(sets.isEmpty, "Variant \(variant) should have no supplemental on deload")
        }
    }

    // MARK: - All Sets

    func testAllSets_BBB_Week1_Count() {
        let sets = ProgramEngine.allSets(trainingMax: 200, week: 1, variant: .boringButBig, roundTo: 5.0)
        // 3 warmup + 3 main + 5 supplemental = 11
        XCTAssertEqual(sets.count, 11)

        let warmups = sets.filter { $0.setType == .warmup }
        let mains = sets.filter { $0.setType == .main }
        let supps = sets.filter { $0.setType == .supplemental }
        XCTAssertEqual(warmups.count, 3)
        XCTAssertEqual(mains.count, 3)
        XCTAssertEqual(supps.count, 5)
    }

    func testAllSets_Standard_Week1_Count() {
        let sets = ProgramEngine.allSets(trainingMax: 200, week: 1, variant: .standard, roundTo: 5.0)
        // 3 warmup + 3 main + 0 supplemental = 6
        XCTAssertEqual(sets.count, 6)
    }

    // MARK: - Rounding

    func testMainSets_Rounding_To2_5() {
        let sets = ProgramEngine.mainSets(trainingMax: 135, week: 1, variant: .standard, roundTo: 2.5)
        // 65% of 135 = 87.75, rounded to 87.5
        XCTAssertEqual(sets[0].weight, 87.5)
        // 75% of 135 = 101.25, rounded to 101.25 -> nope, 2.5 rounding: 100.0
        // Actually (101.25 / 2.5).rounded() * 2.5 = 40.5.rounded() * 2.5 = 41 * 2.5 = 102.5
        XCTAssertEqual(sets[1].weight, 102.5)
    }

    // MARK: - Edge Cases

    func testMainSets_WeekClamping() {
        // Week 0 and week 7 should clamp to valid range
        let week0 = ProgramEngine.mainSets(trainingMax: 200, week: 0, variant: .standard, roundTo: 5.0)
        let week1 = ProgramEngine.mainSets(trainingMax: 200, week: 1, variant: .standard, roundTo: 5.0)
        // Week 0 should clamp to week 1
        XCTAssertEqual(week0.count, week1.count)
        XCTAssertEqual(week0[0].weight, week1[0].weight)

        let week7 = ProgramEngine.mainSets(trainingMax: 200, week: 7, variant: .standard, roundTo: 5.0)
        let week6 = ProgramEngine.mainSets(trainingMax: 200, week: 6, variant: .standard, roundTo: 5.0)
        XCTAssertEqual(week7.count, week6.count)
        XCTAssertEqual(week7[0].weight, week6[0].weight)
    }
}
