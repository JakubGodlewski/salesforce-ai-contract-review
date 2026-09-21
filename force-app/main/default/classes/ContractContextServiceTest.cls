@IsTest
private class ContractContextServiceTest {

    @IsTest
    static void returnsMappedOpportunityAndContractContext() {
        ContractAnalysisTestDataFactory.Scenario scenario =
            ContractAnalysisTestDataFactory.createCompleteScenario();

        Test.startTest();
        ContractContext context =
            ContractContextService.getContext(scenario.opportunity.Id);
        Test.stopTest();

        Assert.areEqual(scenario.opportunity.Id, context.opportunityId);
        Assert.areEqual(scenario.opportunity.Name, context.opportunityName);
        Assert.areEqual('Acme Sp. z o.o.', context.accountName);
        Assert.areEqual(120000, context.amount);
        Assert.areEqual(10, context.discount);
        Assert.areEqual('Net 30', context.paymentTerms);
        Assert.areEqual(60, context.noticePeriodDays);
        Assert.areEqual(scenario.contract.Id, context.contractId);
        Assert.areEqual(Date.newInstance(2026, 11, 1), context.contractStartDate);
        Assert.areEqual(Date.newInstance(2027, 10, 31), context.contractEndDate);
        Assert.areEqual(12, context.contractTermMonths);
    }

    @IsTest
    static void throwsWhenOpportunityHasNoContract() {
        Account account = ContractAnalysisTestDataFactory.createAccount();
        Opportunity opportunity =
            ContractAnalysisTestDataFactory.createOpportunity(account.Id, null);

        try {
            ContractContextService.getContext(opportunity.Id);
            Assert.fail('Expected ContractContextException.');
        } catch (ContractContextService.ContractContextException caughtException) {
            Assert.areEqual(
                'Opportunity does not have a Contract assigned.',
            caughtException.getMessage()
            );
        }
    }

    @IsTest
    static void throwsWhenOpportunityDoesNotExist() {
        Id missingOpportunityId = Id.valueOf('006000000000000AAA');

        try {
            ContractContextService.getContext(missingOpportunityId);
            Assert.fail('Expected QueryException.');
        } catch (QueryException caughtException) {
            Assert.isTrue(caughtException.getMessage().contains('List has no rows'));
        }
    }
}
