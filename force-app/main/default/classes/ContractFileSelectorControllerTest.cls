@IsTest
private class ContractFileSelectorControllerTest {

    @IsTest
    static void returnsAvailablePdfOptionsForOpportunityContract() {
        ContractAnalysisTestDataFactory.Scenario scenario =
            ContractAnalysisTestDataFactory.createCompleteScenario();

        Test.startTest();
        List<ContractFileService.PdfOption> options =
            ContractFileSelectorController.getAvailablePdfs(
                scenario.opportunity.Id
            );
        Test.stopTest();

        Assert.areEqual(1, options.size());
        Assert.areEqual(
            scenario.contentVersion.ContentDocumentId,
            options[0].documentId
        );
        Assert.areEqual(scenario.contentVersion.Id, options[0].contentVersionId);
        Assert.areEqual('Contract Analysis Test PDF', options[0].title);
        Assert.isNotNull(options[0].createdDate);
    }

    @IsTest
    static void returnsNoPdfOptionsWhenOpportunityHasNoContract() {
        Account account = ContractAnalysisTestDataFactory.createAccount();
        Opportunity opportunity = ContractAnalysisTestDataFactory.createOpportunity(
            account.Id,
            null
        );

        Test.startTest();
        List<ContractFileService.PdfOption> options =
            ContractFileSelectorController.getAvailablePdfs(opportunity.Id);
        Test.stopTest();

        Assert.isTrue(options.isEmpty());
    }
}
