@IsTest
private class ContractReviewServiceTest {

    @IsTest
    static void persistsMatchWithoutDiscrepancies() {
        ContractAnalysisTestDataFactory.Scenario scenario =
            ContractAnalysisTestDataFactory.createCompleteScenario();
        ContractAnalysisResult result = buildResult(
            new List<String>{'MATCH'}
        );

        Test.startTest();
        Id reviewId = ContractReviewService.saveReview(
            buildContext(scenario),
            result
        );
        Test.stopTest();

        Contract_Review__c review = [
            SELECT Id, Overall_Result__c, Discrepancy_Count__c, Summary__c
            FROM Contract_Review__c
            WHERE Id = :reviewId
        ];
        Assert.areEqual('MATCH', review.Overall_Result__c);
        Assert.areEqual(0, review.Discrepancy_Count__c);
        Assert.areEqual('Test summary', review.Summary__c);
        Assert.areEqual(
            0,
            [SELECT Count() FROM Contract_Discrepancy__c WHERE Contract_Review__c = :reviewId]
        );
    }

    @IsTest
    static void persistsExactlyThreeMismatchesWithAllValues() {
        ContractAnalysisTestDataFactory.Scenario scenario =
            ContractAnalysisTestDataFactory.createCompleteScenario();
        ContractAnalysisResult result = buildResult(
            new List<String>{'MISMATCH', 'MISMATCH', 'MISMATCH'}
        );

        Test.startTest();
        Id reviewId = ContractReviewService.saveReview(
            buildContext(scenario),
            result
        );
        Test.stopTest();

        Contract_Review__c review = [
            SELECT Overall_Result__c, Discrepancy_Count__c
            FROM Contract_Review__c
            WHERE Id = :reviewId
        ];
        Assert.areEqual('MISMATCH', review.Overall_Result__c);
        Assert.areEqual(3, review.Discrepancy_Count__c);

        List<Contract_Discrepancy__c> discrepancies = [
            SELECT Field__c, Salesforce_Source__c, Salesforce_Value__c,
                Contract_Value__c, Status__c, Severity__c, Confidence__c,
                Contract_Evidence__c, Explanation__c
            FROM Contract_Discrepancy__c
            WHERE Contract_Review__c = :reviewId
            ORDER BY Field__c
        ];
        Assert.areEqual(3, discrepancies.size());
        Map<String, Contract_Discrepancy__c> discrepanciesByField =
            new Map<String, Contract_Discrepancy__c>();
        for (Contract_Discrepancy__c discrepancy : discrepancies) {
            discrepanciesByField.put(discrepancy.Field__c, discrepancy);
        }
        Assert.areEqual(
            new Set<String>{'amount', 'discount', 'noticePeriodDays'},
            discrepanciesByField.keySet()
        );
        assertDiscrepancy(
            discrepanciesByField.get('amount'),
            '120000', '115000', 'HIGH', 0.99,
            'The contract states 115000.', 'Amount differs.'
        );
        assertDiscrepancy(
            discrepanciesByField.get('discount'),
            '10', '15', 'MEDIUM', 0.95,
            'The contract states 15%.', 'Discount differs.'
        );
        assertDiscrepancy(
            discrepanciesByField.get('noticePeriodDays'),
            '60', '30', 'MEDIUM', 0.93,
            'The contract states 30 days.', 'Notice period differs.'
        );
    }

    @IsTest
    static void persistsUnknownAsReviewRequired() {
        assertReviewRequired('UNKNOWN');
    }

    @IsTest
    static void persistsAmbiguousAsReviewRequired() {
        assertReviewRequired('AMBIGUOUS');
    }

    @IsTest
    static void validatesRequiredInputs() {
        ContractAnalysisResult result = buildResult(new List<String>{'MATCH'});

        try {
            ContractReviewService.saveReview(null, result);
            Assert.fail('Expected ContractReviewException.');
        } catch (ContractReviewService.ContractReviewException caughtException) {
            Assert.areEqual('Contract context cannot be null.', caughtException.getMessage());
        }

        ContractContext context = new ContractContext();
        try {
            ContractReviewService.saveReview(context, result);
            Assert.fail('Expected ContractReviewException.');
        } catch (ContractReviewService.ContractReviewException caughtException) {
            Assert.areEqual('Opportunity Id cannot be null.', caughtException.getMessage());
        }
    }

    private static void assertReviewRequired(String status) {
        ContractAnalysisTestDataFactory.Scenario scenario =
            ContractAnalysisTestDataFactory.createCompleteScenario();
        Id reviewId = ContractReviewService.saveReview(
            buildContext(scenario),
            buildResult(new List<String>{status})
        );

        Contract_Review__c review = [
            SELECT Overall_Result__c, Discrepancy_Count__c
            FROM Contract_Review__c
            WHERE Id = :reviewId
        ];
        Assert.areEqual('REVIEW_REQUIRED', review.Overall_Result__c);
        Assert.areEqual(1, review.Discrepancy_Count__c);
        Contract_Discrepancy__c discrepancy = [
            SELECT Status__c
            FROM Contract_Discrepancy__c
            WHERE Contract_Review__c = :reviewId
            LIMIT 1
        ];
        Assert.areEqual(status, discrepancy.Status__c);
    }

    private static ContractContext buildContext(
        ContractAnalysisTestDataFactory.Scenario scenario
    ) {
        ContractContext context = new ContractContext();
        context.opportunityId = scenario.opportunity.Id;
        context.contractId = scenario.contract.Id;
        return context;
    }

    private static ContractAnalysisResult buildResult(List<String> statuses) {
        ContractAnalysisResult result = new ContractAnalysisResult();
        result.summary = 'Test summary';
        result.comparisons = new List<ContractAnalysisResult.Comparison>();
        List<String> fields = new List<String>{
            'amount', 'discount', 'noticePeriodDays'
        };
        List<String> salesforceValues = new List<String>{'120000', '10', '60'};
        List<String> contractValues = new List<String>{'115000', '15', '30'};
        List<String> severities = new List<String>{'HIGH', 'MEDIUM', 'MEDIUM'};
        List<Decimal> confidences = new List<Decimal>{0.99, 0.95, 0.93};
        List<String> evidence = new List<String>{
            'The contract states 115000.',
            'The contract states 15%.',
            'The contract states 30 days.'
        };
        List<String> explanations = new List<String>{
            'Amount differs.',
            'Discount differs.',
            'Notice period differs.'
        };
        Integer index = 0;
        for (String status : statuses) {
            ContractAnalysisResult.Comparison comparison =
                new ContractAnalysisResult.Comparison();
            comparison.field = fields[index];
            comparison.salesforceSource = 'Opportunity';
            comparison.salesforceValue = salesforceValues[index];
            comparison.contractValue = contractValues[index];
            comparison.status = status;
            comparison.severity = severities[index];
            comparison.confidence = confidences[index];
            comparison.contractEvidence = evidence[index];
            comparison.explanation = explanations[index];
            result.comparisons.add(comparison);
            index++;
        }
        return result;
    }

    private static void assertDiscrepancy(
        Contract_Discrepancy__c discrepancy,
        String salesforceValue,
        String contractValue,
        String severity,
        Decimal confidence,
        String evidence,
        String explanation
    ) {
        Assert.isNotNull(discrepancy);
        Assert.areEqual('Opportunity', discrepancy.Salesforce_Source__c);
        Assert.areEqual(salesforceValue, discrepancy.Salesforce_Value__c);
        Assert.areEqual(contractValue, discrepancy.Contract_Value__c);
        Assert.areEqual('MISMATCH', discrepancy.Status__c);
        Assert.areEqual(severity, discrepancy.Severity__c);
        Assert.areEqual(confidence, discrepancy.Confidence__c);
        Assert.areEqual(evidence, discrepancy.Contract_Evidence__c);
        Assert.areEqual(explanation, discrepancy.Explanation__c);
    }
}
