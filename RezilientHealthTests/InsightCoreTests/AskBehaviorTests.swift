@testable import RezilientHealth
import Foundation
import Testing

/// Protects the question flow's grounding and failure contract.
@Suite struct AskBehaviorTests {

    @Test func missingNewContractFieldsAndNumericObservationsAreRejected() async {
        let oldShape = #"{"status":"answered","observations":[],"general_info":[],"limitations":[]}"#
        let numericProse = #"{"status":"answered","takeaway":"Your activity changed.","display_metrics":["steps"],"observations":[{"text":"Your steps averaged 999999.","metrics":["steps"]}],"general_info":[],"limitations":[]}"#
        for json in [oldShape, numericProse] {
            let result = await InsightAssistant(client: ScriptedClient(.success(json))).ask("What changed?", context: Fixture.stepsOnlyContext)
            #expect(result == .failure(.unreadableResponse))
        }
    }

    @Test func freeTextReplyIsNeverShownAsAnAnswer() async {
        let client = ScriptedClient(.success("Sure! Your steps look great this week."))
        let result = await InsightAssistant(client: client).ask("How am I doing?", context: Fixture.stepsOnlyContext)
        #expect(result == .failure(.unreadableResponse))
    }

    @Test func observationsNotBackedByAvailableDataAreRemovedAndDisclosed() throws {
        // Only steps have data; the model claims something about sleep and
        // makes an uncited claim. Both must go; general info stays separate.
        let answer = InsightAnswer(
            status: .answered,
            observations: [
                .init(text: "Your recorded activity was steady.", metrics: ["steps"]),
                .init(text: "Your sleep improved.", metrics: ["sleep"]),
                .init(text: "You seem stressed.", metrics: []),
            ],
            generalInfo: ["Regular movement supports heart health."],
            limitations: []
        )
        let (validated, removed) = try AnswerValidator.validate(answer, context: Fixture.stepsOnlyContext)

        #expect(removed == 2)
        #expect(validated.observations.map(\.metrics) == [["steps"]])
        #expect(validated.generalInfo == ["Regular movement supports heart health."])
        #expect(validated.limitations.last?.contains("2 statements were hidden") == true)
    }

    @Test func possibleEmergencyIsAnsweredLocallyWithoutCallingTheModel() async throws {
        let client = ScriptedClient()
        let result = await InsightAssistant(client: client).ask("I have chest pain and my heart rate is high", context: Fixture.stepsOnlyContext)

        #expect(client.calls.isEmpty)
        let answered = try result.get()
        #expect(answered.answer.status == .needsClinician)
        #expect(answered.answer.generalInfo.first?.contains("911") == true)
    }

    @Test func deterministicMockRefusesDiagnosisAndUntrackedData() {
        let context = Fixture.stepsOnlyContext
        #expect(MockModelClient.answer(question: "Do I have sleep apnea?", context: context).status == .needsClinician)
        #expect(MockModelClient.answer(question: "What's my blood pressure trend?", context: context).status == .insufficientData)
        #expect(MockModelClient.answer(question: "What do you notice about my activity this week?", context: context).status == .answered)
    }
}
