@IsTest
private class ContractAnalysisSecurityTest {

    @testSetup
    static void setup() {
        ContractAnalysisTestDataFactory.createTestUsersAndData();
    }

    @IsTest
    static void leastPrivilegeUser_CanAnalyzeOwnedOpportunity() {
        assertAnalysisForUser(false);
    }

    @IsTest
    static void aiAdminContext_CanAnalyzeOwnedOpportunity() {
        assertAnalysisForUser(true);
    }

    @IsTest
    static void leastPrivilegeUser_CannotAnalyzeUnsharedOpportunity() {
        User leastPrivilegeUser =
            ContractAnalysisTestDataFactory.getTestUser(false);
        User aiAdminUser =
            ContractAnalysisTestDataFactory.getTestUser(true);
        ContractAnalysisTestDataFactory.Scenario otherUserScenario =
            ContractAnalysisTestDataFactory.getScenarioForOwner(aiAdminUser.Id);

        System.runAs(leastPrivilegeUser) {
            try {
                ContractAnalysisService.analyze(
                    otherUserScenario.opportunity.Id
                );
                Assert.fail(
                    'Expected analysis to fail for an inaccessible Opportunity.'
                );
            } catch (QueryException caughtException) {
                Assert.isTrue(
                    caughtException.getMessage().contains('List has no rows')
                );
            }

            Assert.areEqual(
                0,
                [SELECT Count() FROM Contract_Review__c
                 WHERE Opportunity__c = :otherUserScenario.opportunity.Id]
            );
            Assert.areEqual(
                0,
                [SELECT Count() FROM Contract_Discrepancy__c
                 WHERE Contract_Review__c IN (
                     SELECT Id FROM Contract_Review__c
                     WHERE Opportunity__c = :otherUserScenario.opportunity.Id
                 )]
            );
        }
    }

    private static void assertAnalysisForUser(Boolean admin) {
        User testUser = ContractAnalysisTestDataFactory.getTestUser(admin);
        ContractAnalysisTestDataFactory.Scenario scenario =
            ContractAnalysisTestDataFactory.getScenarioForOwner(testUser.Id);
        System.runAs(testUser) {
            Test.setMock(HttpCalloutMock.class, ClaudeHttpCalloutMock.success());
            Test.startTest();
            ContractAnalysisService.AnalysisOutcome outcome =
                ContractAnalysisService.analyze(scenario.opportunity.Id);
            Test.stopTest();

            Assert.areEqual('MISMATCH', outcome.result.overallStatus);
            Assert.isNotNull(outcome.contractReviewId);
            Assert.areEqual(
                3,
                [SELECT Count() FROM Contract_Discrepancy__c
                 WHERE Contract_Review__c = :outcome.contractReviewId]
            );
        }
    }
}
