@IsTest
private class ContractAnalysisActionTest {

    @IsTest
    static void returnsInvocableResponseForMismatchAnalysis() {
        ContractAnalysisTestDataFactory.Scenario scenario =
            ContractAnalysisTestDataFactory.createCompleteScenario();
        Test.setMock(HttpCalloutMock.class, ClaudeHttpCalloutMock.success());

        ContractAnalysisAction.Request request =
            new ContractAnalysisAction.Request();
        request.opportunityId = scenario.opportunity.Id;
        request.contentVersionId = scenario.contentVersion.Id;

        Test.startTest();
        List<ContractAnalysisAction.Response> responses =
            ContractAnalysisAction.analyze(
                new List<ContractAnalysisAction.Request>{request}
            );
        Test.stopTest();

        Assert.areEqual(1, responses.size());
        Assert.isNotNull(responses[0].contractReviewId);
        Assert.areEqual('MISMATCH', responses[0].overallStatus);
        Assert.areEqual(3, responses[0].discrepancyCount);
        Assert.areEqual(
            'Three contractual values differ from Salesforce.',
            responses[0].summary
        );
        Assert.areEqual(
            1,
            [SELECT Count() FROM Contract_Review__c WHERE Id = :responses[0].contractReviewId]
        );
    }

    @IsTest
    static void rejectsNullRequestOpportunityId() {
        ContractAnalysisAction.Request request =
            new ContractAnalysisAction.Request();
        request.opportunityId = null;

        try {
            ContractAnalysisAction.analyze(
                new List<ContractAnalysisAction.Request>{request}
            );
            Assert.fail('Expected ContractAnalysisException.');
        } catch (ContractAnalysisService.ContractAnalysisException caughtException) {
            Assert.areEqual('Opportunity Id cannot be null.', caughtException.getMessage());
        }
    }
}
