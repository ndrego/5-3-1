import XCTest
@testable import FiveThreeOne

final class StrongImporterTests: XCTestCase {

    // MARK: - CSV Line Parsing

    func testParseCSVLine_Simple() {
        let fields = StrongImporter.parseCSVLine("a,b,c")
        XCTAssertEqual(fields, ["a", "b", "c"])
    }

    func testParseCSVLine_QuotedComma() {
        let fields = StrongImporter.parseCSVLine("\"hello, world\",b,c")
        XCTAssertEqual(fields[0], "hello, world")
        XCTAssertEqual(fields.count, 3)
    }

    func testParseCSVLine_TrimsWhitespace() {
        let fields = StrongImporter.parseCSVLine(" a , b , c ")
        XCTAssertEqual(fields, ["a", "b", "c"])
    }

    func testParseCSVLine_EmptyFields() {
        let fields = StrongImporter.parseCSVLine("a,,c")
        XCTAssertEqual(fields, ["a", "", "c"])
    }

    // MARK: - Duration Parsing

    func testParseDuration_HoursAndMinutes() {
        let seconds = StrongImporter.parseDuration("1h 23m")
        XCTAssertEqual(seconds, 3600 + 23 * 60) // 4980
    }

    func testParseDuration_MinutesAndSeconds() {
        let seconds = StrongImporter.parseDuration("45m 30s")
        XCTAssertEqual(seconds, 45 * 60 + 30) // 2730
    }

    func testParseDuration_MinutesOnly() {
        let seconds = StrongImporter.parseDuration("30m")
        XCTAssertEqual(seconds, 1800)
    }

    func testParseDuration_HoursOnly() {
        let seconds = StrongImporter.parseDuration("2h")
        XCTAssertEqual(seconds, 7200)
    }

    func testParseDuration_Empty() {
        let seconds = StrongImporter.parseDuration("")
        XCTAssertEqual(seconds, 0)
    }

    // MARK: - Unilateral Detection

    func testIsLikelyUnilateral_BulgarianSplitSquat() {
        XCTAssertTrue(StrongImporter.isLikelyUnilateral("Bulgarian Split Squat"))
    }

    func testIsLikelyUnilateral_SingleArmRow() {
        XCTAssertTrue(StrongImporter.isLikelyUnilateral("Single Arm Dumbbell Row"))
    }

    func testIsLikelyUnilateral_Lunge() {
        XCTAssertTrue(StrongImporter.isLikelyUnilateral("Walking Lunge"))
    }

    func testIsLikelyUnilateral_DumbbellCurl() {
        XCTAssertTrue(StrongImporter.isLikelyUnilateral("Dumbbell Curl"))
    }

    func testIsLikelyUnilateral_BenchPress() {
        XCTAssertFalse(StrongImporter.isLikelyUnilateral("Bench Press"))
    }

    func testIsLikelyUnilateral_Squat() {
        XCTAssertFalse(StrongImporter.isLikelyUnilateral("Squat (Barbell)"))
    }

    // MARK: - Exercise Name Normalization

    func testNormalizeExerciseName_DirectMatch() {
        let known: Set<String> = ["Bench Press", "Squat"]
        let result = StrongImporter.normalizeExerciseName("Bench Press", knownNames: known)
        XCTAssertEqual(result, "Bench Press")
    }

    func testNormalizeExerciseName_StripsParenthetical() {
        let known: Set<String> = ["Bench Press", "Squat"]
        let result = StrongImporter.normalizeExerciseName("Bench Press (Barbell)", knownNames: known)
        XCTAssertEqual(result, "Bench Press")
    }

    func testNormalizeExerciseName_NoMatch_ReturnsOriginal() {
        let known: Set<String> = ["Bench Press"]
        let result = StrongImporter.normalizeExerciseName("Tricep Pushdown (Cable)", knownNames: known)
        XCTAssertEqual(result, "Tricep Pushdown (Cable)")
    }

    // MARK: - Category Guessing

    func testGuessCategory_PullExercises() {
        XCTAssertEqual(StrongImporter.guessCategory(for: "Barbell Curl"), .pull)
        XCTAssertEqual(StrongImporter.guessCategory(for: "Dumbbell Row"), .pull)
        XCTAssertEqual(StrongImporter.guessCategory(for: "Lat Pulldown"), .pull)
        XCTAssertEqual(StrongImporter.guessCategory(for: "Chin Up"), .pull)
        XCTAssertEqual(StrongImporter.guessCategory(for: "Face Pull"), .pull)
    }

    func testGuessCategory_SingleLegCore() {
        XCTAssertEqual(StrongImporter.guessCategory(for: "Walking Lunge"), .singleLegCore)
        XCTAssertEqual(StrongImporter.guessCategory(for: "Leg Press"), .singleLegCore)
        XCTAssertEqual(StrongImporter.guessCategory(for: "Plank"), .singleLegCore)
        XCTAssertEqual(StrongImporter.guessCategory(for: "Hip Thrust"), .singleLegCore)
        XCTAssertEqual(StrongImporter.guessCategory(for: "Calf Raise"), .singleLegCore)
    }

    func testGuessCategory_Push_Default() {
        XCTAssertEqual(StrongImporter.guessCategory(for: "Overhead Press"), .push)
        XCTAssertEqual(StrongImporter.guessCategory(for: "Tricep Pushdown"), .push)
    }

    // MARK: - Equipment Guessing

    func testGuessEquipment() {
        XCTAssertEqual(StrongImporter.guessEquipment(for: "Bench Press (Barbell)"), "barbell")
        XCTAssertEqual(StrongImporter.guessEquipment(for: "Dumbbell Row"), "dumbbell")
        XCTAssertEqual(StrongImporter.guessEquipment(for: "Cable Fly"), "cable")
        XCTAssertEqual(StrongImporter.guessEquipment(for: "Leg Press (Machine)"), "machine")
        XCTAssertEqual(StrongImporter.guessEquipment(for: "Pull Up (Bodyweight)"), "bodyweight")
        XCTAssertEqual(StrongImporter.guessEquipment(for: "Something Weird"), "other")
    }

    // MARK: - Full CSV Parsing

    func testParseCSV_ValidRows() {
        let csv = """
        Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE
        2024-01-15 08:00:00,Morning,1h 0m,Squat (Barbell),1,225,5,,,,,
        2024-01-15 08:00:00,Morning,1h 0m,Squat (Barbell),2,245,3,,,,,
        2024-01-15 08:00:00,Morning,1h 0m,Bench Press (Barbell),1,185,5,,,,,
        """
        let (rows, errors) = StrongImporter.parseCSV(csv)
        XCTAssertEqual(rows.count, 3)
        XCTAssertTrue(errors.isEmpty)
        XCTAssertEqual(rows[0].exerciseName, "Squat (Barbell)")
        XCTAssertEqual(rows[0].weight, 225)
        XCTAssertEqual(rows[0].reps, 5)
        XCTAssertEqual(rows[2].exerciseName, "Bench Press (Barbell)")
    }

    func testParseCSV_EmptyCSV() {
        let (rows, errors) = StrongImporter.parseCSV("")
        XCTAssertTrue(rows.isEmpty)
        XCTAssertEqual(errors.count, 1) // "CSV file is empty or has no data rows"
    }

    func testParseCSV_HeaderOnly() {
        let csv = "Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE\n2024-01-15 08:00:00,Morning,1h 0m,Squat (Barbell),1,225,5,,,,,"
        let (rows, errors) = StrongImporter.parseCSV(csv)
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(errors.isEmpty)
    }

    func testParseCSV_WithRPE() {
        let csv = """
        Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE
        2024-01-15 08:00:00,Morning,1h 0m,Squat (Barbell),1,225,5,,,,, 8.5
        """
        let (rows, _) = StrongImporter.parseCSV(csv)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].rpe, 8.5)
    }
}
