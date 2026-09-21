@IsTest
private class ContractAnalysisServiceTest {

    @IsTest
    static void completesAnalysisAndPersistsThreeMismatches() {
        ContractAnalysisTestDataFactory.Scenario scenario =
            ContractAnalysisTestDataFactory.createCompleteScenario();
        Test.setMock(HttpCalloutMock.class, ClaudeHttpCalloutMock.success());

        Test.startTest();
        ContractAnalysisService.AnalysisOutcome outcome =
            ContractAnalysisService.analyze(scenario.opportunity.Id);
        Test.stopTest();

        Assert.isNotNull(outcome);
        Assert.isNotNull(outcome.contractReviewId);
        Assert.areEqual('MISMATCH', outcome.result.overallStatus);
        Assert.areEqual(8, outcome.result.comparisons.size());
        Assert.areEqual(
            1,
            [SELECT Count() FROM Contract_Review__c WHERE Id = :outcome.contractReviewId]
        );
        Assert.areEqual(
            3,
            [SELECT Count() FROM Contract_Discrepancy__c WHERE Contract_Review__c = :outcome.contractReviewId]
        );

        Map<String, Contract_Discrepancy__c> discrepanciesByField =
            new Map<String, Contract_Discrepancy__c>();
        for (Contract_Discrepancy__c discrepancy : [
            SELECT Field__c, Salesforce_Value__c, Contract_Value__c,
                Status__c, Severity__c
            FROM Contract_Discrepancy__c
            WHERE Contract_Review__c = :outcome.contractReviewId
        ]) {
            discrepanciesByField.put(discrepancy.Field__c, discrepancy);
        }
        Assert.areEqual(
            new Set<String>{'amount', 'discount', 'noticePeriodDays'},
            discrepanciesByField.keySet()
        );
        Assert.areEqual('120000', discrepanciesByField.get('amount').Salesforce_Value__c);
        Assert.areEqual('115000', discrepanciesByField.get('amount').Contract_Value__c);
        Assert.areEqual('MISMATCH', discrepanciesByField.get('amount').Status__c);
        Assert.areEqual('HIGH', discrepanciesByField.get('amount').Severity__c);
        Assert.areEqual('10', discrepanciesByField.get('discount').Salesforce_Value__c);
        Assert.areEqual('15', discrepanciesByField.get('discount').Contract_Value__c);
        Assert.areEqual('60', discrepanciesByField.get('noticePeriodDays').Salesforce_Value__c);
        Assert.areEqual('30', discrepanciesByField.get('noticePeriodDays').Contract_Value__c);
    }

    @IsTest
    static void rejectsNullOpportunityId() {
        try {
            ContractAnalysisService.analyze(null);
            Assert.fail('Expected ContractAnalysisException.');
        } catch (ContractAnalysisService.ContractAnalysisException caughtException) {
            Assert.areEqual('Opportunity Id cannot be null.', caughtException.getMessage());
        }
    }

    @IsTest
    static void propagatesMissingOpportunityFailure() {
        Id missingOpportunityId = Id.valueOf('006000000000000AAA');

        try {
            ContractAnalysisService.analyze(missingOpportunityId);
            Assert.fail('Expected QueryException.');
        } catch (QueryException caughtException) {
            Assert.isTrue(caughtException.getMessage().contains('List has no rows'));
        }
    }

    @IsTest
    static void rejectsOpportunityWithoutContract() {
        Account account = ContractAnalysisTestDataFactory.createAccount();
        Opportunity opportunity =
            ContractAnalysisTestDataFactory.createOpportunity(account.Id, null);

        try {
            ContractAnalysisService.analyze(opportunity.Id);
            Assert.fail('Expected ContractContextException.');
        } catch (ContractContextService.ContractContextException caughtException) {
            Assert.areEqual(
                'Opportunity does not have a Contract assigned.',
            caughtException.getMessage()
            );
        }
    }

    @IsTest
    static void rejectsContractWithoutPdf() {
        Account account = ContractAnalysisTestDataFactory.createAccount();
        Contract contract = ContractAnalysisTestDataFactory.createContract(account.Id);
        Opportunity opportunity =
            ContractAnalysisTestDataFactory.createOpportunity(account.Id, contract.Id);

        try {
            ContractAnalysisService.analyze(opportunity.Id);
            Assert.fail('Expected ContractFileException.');
        } catch (ContractFileService.ContractFileException caughtException) {
            Assert.isTrue(caughtException.getMessage().contains('No files found'));
        }
    }

    @IsTest
    static void propagatesHttpFailure() {
        ContractAnalysisTestDataFactory.Scenario scenario =
            ContractAnalysisTestDataFactory.createCompleteScenario();
        Test.setMock(HttpCalloutMock.class, ClaudeHttpCalloutMock.apiError(500));

        try {
            Test.startTest();
            ContractAnalysisService.analyze(scenario.opportunity.Id);
            Test.stopTest();
            Assert.fail('Expected ClaudeClientException.');
        } catch (ClaudeClient.ClaudeClientException caughtException) {
            Assert.isTrue(caughtException.getMessage().contains('HTTP 500'));
        }
    }

    @IsTest
    static void rejectsMalformedClaudeJson() {
        ContractAnalysisTestDataFactory.Scenario scenario =
            ContractAnalysisTestDataFactory.createCompleteScenario();
        Test.setMock(HttpCalloutMock.class, ClaudeHttpCalloutMock.malformedContentJson());

        try {
            Test.startTest();
            ContractAnalysisService.analyze(scenario.opportunity.Id);
            Test.stopTest();
            Assert.fail('Expected ClaudeClientException.');
        } catch (ClaudeClient.ClaudeClientException caughtException) {
            Assert.isTrue(caughtException.getMessage().contains('invalid JSON'));
        }
    }

    @IsTest
    static void rejectsMaxTokensResponse() {
        ContractAnalysisTestDataFactory.Scenario scenario =
            ContractAnalysisTestDataFactory.createCompleteScenario();
        Test.setMock(HttpCalloutMock.class, ClaudeHttpCalloutMock.maxTokens());

        try {
            Test.startTest();
            ContractAnalysisService.analyze(scenario.opportunity.Id);
            Test.stopTest();
            Assert.fail('Expected ClaudeClientException.');
        } catch (ClaudeClient.ClaudeClientException caughtException) {
            Assert.isTrue(caughtException.getMessage().contains('truncated'));
        }
    }

    @IsTest
    static void rejectsUnsupportedStatus() {
        assertInvalidAnalysis(
            '{"overallStatus":"MISMATCH","summary":"x","comparisons":[' +
            '{"field":"amount","status":"INVALID","severity":"HIGH","confidence":0.9}]}'
        );
    }

    @IsTest
    static void rejectsUnsupportedSeverity() {
        assertInvalidAnalysis(
            '{"overallStatus":"MISMATCH","summary":"x","comparisons":[' +
            '{"field":"amount","status":"MISMATCH","severity":"CRITICAL","confidence":0.9}]}'
        );
    }

    @IsTest
    static void rejectsHighConfidence() {
        assertInvalidAnalysis(
            '{"overallStatus":"MISMATCH","summary":"x","comparisons":[' +
            '{"field":"amount","status":"MISMATCH","severity":"HIGH","confidence":1.1}]}'
        );
    }

    @IsTest
    static void rejectsNegativeConfidence() {
        assertInvalidAnalysis(
            '{"overallStatus":"MISMATCH","summary":"x","comparisons":[' +
            '{"field":"amount","status":"MISMATCH","severity":"HIGH","confidence":-0.1}]}'
        );
    }

    @IsTest
    static void calculatesMatchForAllMatches() {
        Assert.areEqual('MATCH', analyzeWithStatuses(new List<String>{'MATCH'}));
    }

    @IsTest
    static void calculatesReviewRequiredForUnknown() {
        Assert.areEqual(
            'REVIEW_REQUIRED',
            analyzeWithStatuses(new List<String>{'MATCH', 'UNKNOWN'})
        );
    }

    @IsTest
    static void calculatesReviewRequiredForAmbiguous() {
        Assert.areEqual(
            'REVIEW_REQUIRED',
            analyzeWithStatuses(new List<String>{'MATCH', 'AMBIGUOUS'})
        );
    }

    @IsTest
    static void calculatesReviewRequiredForUnknownAndAmbiguous() {
        Assert.areEqual(
            'REVIEW_REQUIRED',
            analyzeWithStatuses(new List<String>{'MATCH', 'UNKNOWN', 'AMBIGUOUS'})
        );
    }

    @IsTest
    static void calculatesMismatchForMatchAndMismatch() {
        Assert.areEqual(
            'MISMATCH',
            analyzeWithStatuses(new List<String>{'MATCH', 'MISMATCH'})
        );
    }

    @IsTest
    static void calculatesMismatchBeforeReviewRequired() {
        Assert.areEqual(
            'MISMATCH',
            analyzeWithStatuses(new List<String>{'MISMATCH', 'UNKNOWN', 'AMBIGUOUS'})
        );
    }

    @IsTest
    static void ignoresClaudeOverallStatus() {
        ContractAnalysisTestDataFactory.Scenario scenario =
            ContractAnalysisTestDataFactory.createCompleteScenario();
        Test.setMock(
            HttpCalloutMock.class,
            new ClaudeHttpCalloutMock(
                200,
                ClaudeHttpCalloutMock.responseWithAnalysis(
                    analysisJson(new List<String>{'MATCH', 'UNKNOWN'}, 'MISMATCH')
                )
            )
        );

        Test.startTest();
        ContractAnalysisService.AnalysisOutcome outcome =
            ContractAnalysisService.analyze(scenario.opportunity.Id);
        Test.stopTest();

        Assert.areEqual('REVIEW_REQUIRED', outcome.result.overallStatus);
    }

    private static String analyzeWithStatuses(List<String> statuses) {
        ContractAnalysisTestDataFactory.Scenario scenario =
            ContractAnalysisTestDataFactory.createCompleteScenario();
        Test.setMock(
            HttpCalloutMock.class,
            new ClaudeHttpCalloutMock(
                200,
                ClaudeHttpCalloutMock.responseWithAnalysis(
                    analysisJson(statuses, 'MISMATCH')
                )
            )
        );

        Test.startTest();
        ContractAnalysisService.AnalysisOutcome outcome =
            ContractAnalysisService.analyze(scenario.opportunity.Id);
        Test.stopTest();

        return outcome.result.overallStatus;
    }

    private static String analysisJson(
        List<String> statuses,
        String overallStatus
    ) {
        List<Object> comparisons = new List<Object>();
        Integer index = 0;

        for (String status : statuses) {
            comparisons.add(new Map<String, Object>{
                'field' => 'testField' + index,
                'salesforceSource' => 'Opportunity',
                'salesforceValue' => 'Salesforce value',
                'contractValue' => 'Contract value',
                'status' => status,
                'severity' => status == 'MATCH' ? 'NONE' : 'MEDIUM',
                'confidence' => 0.9,
                'contractEvidence' => 'Test evidence',
                'explanation' => 'Test explanation'
            });
            index++;
        }

        return JSON.serialize(new Map<String, Object>{
            'overallStatus' => overallStatus,
            'summary' => 'Test summary',
            'comparisons' => comparisons
        });
    }

    private static void assertInvalidAnalysis(String analysisJson) {
        ContractAnalysisTestDataFactory.Scenario scenario =
            ContractAnalysisTestDataFactory.createCompleteScenario();
        Test.setMock(
            HttpCalloutMock.class,
            new ClaudeHttpCalloutMock(
                200,
                ClaudeHttpCalloutMock.responseWithAnalysis(analysisJson)
            )
        );

        try {
            Test.startTest();
            ContractAnalysisService.analyze(scenario.opportunity.Id);
            Assert.fail('Expected ContractAnalysisException.');
        } catch (ContractAnalysisService.ContractAnalysisException caughtException) {
            Assert.isNotNull(caughtException.getMessage());
        } finally {
            Test.stopTest();
        }
    }

}
