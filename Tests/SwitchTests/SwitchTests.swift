import Foundation
@testable import Switch

func testGrammarCoach() {
    let coach = GrammarCoachService.shared
    assert(coach.getCorrection(for: "grammer") == "grammar")
    assert(coach.getCorrection(for: "writting") == "writing")
    assert(coach.getCorrection(for: "coatch") == "coach")
}
