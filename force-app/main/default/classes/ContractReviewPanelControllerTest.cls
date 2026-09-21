@IsTest
private class ContractReviewPanelControllerTest {

    @IsTest
    static void returnsLatestReviewWithDiscrepancies() {
        ContractAnalysisTestDataFactory.Scenario scenario =
            ContractAnalysisTestDataFactory.createCompleteScenario();
        ContractAnalysisResult result = new ContractAnalysisResult();
        result.summary = 'Three contractual values differ from Salesforce.';
        result.comparisons = new List<ContractAnalysisResult.Comparison>{
            comparison('amount', '120000', '115000', 'HIGH'),
            comparison('discount', '10', '15', 'MEDIUM'),
            comparison('noticePeriodDays', '60', '30', 'MEDIUM')
        };

        Id reviewId = ContractReviewService.saveReview(
            buildContext(scenario),
            result
        );

        Test.startTest();
        ContractReviewPanelController.ReviewViewModel viewModel =
            ContractReviewPanelController.getLatestReview(scenario.opportunity.Id);
        Test.stopTest();

        Assert.areEqual(reviewId, viewModel.id);
        Assert.isNotNull(viewModel.analysisDate);
        Assert.areEqual('claude-sonnet-4-6', viewModel.model);
        Assert.areEqual('MISMATCH', viewModel.overallResult);
        Assert.areEqual(3, viewModel.discrepancyCount);
        Assert.areEqual(
            'Three contractual values differ from Salesforce.',
            viewModel.summary
        );
        Assert.areEqual(3, viewModel.discrepancies.size());
        Assert.areEqual(
            new Set<String>{'amount', 'discount', 'noticePeriodDays'},
            discrepancyFields(viewModel)
        );
        ContractReviewPanelController.DiscrepancyViewModel amount =
            findDiscrepancy(viewModel, 'amount');
        Assert.areEqual('Opportunity', amount.salesforceSource);
        Assert.areEqual('120000', amount.salesforceValue);
        Assert.areEqual('115000', amount.contractValue);
        Assert.areEqual('MISMATCH', amount.status);
        Assert.areEqual('HIGH', amount.severity);
        Assert.areEqual(0.95, amount.confidence);
        Assert.areEqual('Evidence from contract.', amount.contractEvidence);
        Assert.areEqual('Values differ.', amount.explanation);
    }

    @IsTest
    static void returnsNullWhenOpportunityHasNoReview() {
        Account account = ContractAnalysisTestDataFactory.createAccount();
        Opportunity opportunity = ContractAnalysisTestDataFactory.createOpportunity(
            account.Id,
            null
        );

        Test.startTest();
        ContractReviewPanelController.ReviewViewModel viewModel =
            ContractReviewPanelController.getLatestReview(opportunity.Id);
        Test.stopTest();

        Assert.isNull(viewModel);
    }

    @IsTest
    static void returnsMostRecentReview() {
        ContractAnalysisTestDataFactory.Scenario scenario =
            ContractAnalysisTestDataFactory.createCompleteScenario();
        ContractAnalysisResult firstResult = new ContractAnalysisResult();
        firstResult.summary = 'Older review';
        firstResult.comparisons = new List<ContractAnalysisResult.Comparison>();
        Id firstReviewId = ContractReviewService.saveReview(
            buildContext(scenario),
            firstResult
        );
        Contract_Review__c firstReview = [
            SELECT Id, Analysis_Date__c
            FROM Contract_Review__c
            WHERE Id = :firstReviewId
        ];
        firstReview.Analysis_Date__c = System.now().addDays(-1);
        update firstReview;

        ContractAnalysisResult secondResult = new ContractAnalysisResult();
        secondResult.summary = 'Latest review';
        secondResult.comparisons = new List<ContractAnalysisResult.Comparison>();
        Id secondReviewId = ContractReviewService.saveReview(
            buildContext(scenario),
            secondResult
        );

        ContractReviewPanelController.ReviewViewModel viewModel =
            ContractReviewPanelController.getLatestReview(scenario.opportunity.Id);

        Assert.areEqual(secondReviewId, viewModel.id);
        Assert.areEqual('Latest review', viewModel.summary);
    }

    @IsTest
    static void nullOpportunityIdThrowsExpectedException() {
        try {
            ContractReviewPanelController.getLatestReview(null);
            Assert.fail('Expected AuraHandledException.');
        } catch (AuraHandledException caughtException) {
            Assert.isNotNull(caughtException);
        }
    }

    private static ContractAnalysisResult.Comparison comparison(
        String field,
        String salesforceValue,
        String contractValue,
        String severity
    ) {
        ContractAnalysisResult.Comparison comparison =
            new ContractAnalysisResult.Comparison();
        comparison.field = field;
        comparison.salesforceSource = 'Opportunity';
        comparison.salesforceValue = salesforceValue;
        comparison.contractValue = contractValue;
        comparison.status = 'MISMATCH';
        comparison.severity = severity;
        comparison.confidence = 0.95;
        comparison.contractEvidence = 'Evidence from contract.';
        comparison.explanation = 'Values differ.';
        return comparison;
    }

    private static ContractContext buildContext(
        ContractAnalysisTestDataFactory.Scenario scenario
    ) {
        ContractContext context = new ContractContext();
        context.opportunityId = scenario.opportunity.Id;
        context.contractId = scenario.contract.Id;
        return context;
    }

    private static Set<String> discrepancyFields(
        ContractReviewPanelController.ReviewViewModel viewModel
    ) {
        Set<String> fields = new Set<String>();
        for (
            ContractReviewPanelController.DiscrepancyViewModel discrepancy :
            viewModel.discrepancies
        ) {
            fields.add(discrepancy.field);
        }
        return fields;
    }

    private static ContractReviewPanelController.DiscrepancyViewModel findDiscrepancy(
        ContractReviewPanelController.ReviewViewModel viewModel,
        String fieldName
    ) {
        for (
            ContractReviewPanelController.DiscrepancyViewModel discrepancy :
            viewModel.discrepancies
        ) {
            if (discrepancy.field == fieldName) {
                return discrepancy;
            }
        }
        Assert.fail('Missing discrepancy for field: ' + fieldName);
        return null;
    }
}
