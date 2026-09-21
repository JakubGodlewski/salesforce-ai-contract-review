public with sharing class ContractReviewService {

    private static final String STATUS_COMPLETED = 'Completed';
    private static final String DEFAULT_MODEL = 'claude-sonnet-4-6';

    private static final Set<String> DISCREPANCY_STATUSES =
        new Set<String>{
            'MISMATCH',
            'UNKNOWN',
            'AMBIGUOUS'
        };


    /**
     * Persists a completed contract analysis in Salesforce.
     *
     * Creates:
     * - one Contract_Review__c
     * - zero or more Contract_Discrepancy__c records
     *
     * MATCH comparisons are intentionally not persisted
     * as discrepancy records.
     */
    public static Id saveReview(
        ContractContext context,
        ContractAnalysisResult result
    ) {

        validateInput(context, result);

        List<ContractAnalysisResult.Comparison> discrepancies =
            getDiscrepancies(result);

        Contract_Review__c review = new Contract_Review__c(
            Opportunity__c = context.opportunityId,
            Contract__c = context.contractId,
            Status__c = STATUS_COMPLETED,
            Analysis_Date__c = System.today(),
            Model__c = DEFAULT_MODEL,
            Overall_Result__c = String.isBlank(result.overallStatus)
                ? determineOverallResult(result)
                : result.overallStatus,
            Discrepancy_Count__c = discrepancies.size(),
            Summary__c = result.summary
        );

        insert review;

        List<Contract_Discrepancy__c> recordsToInsert =
            new List<Contract_Discrepancy__c>();

        for (
            ContractAnalysisResult.Comparison comparison :
            discrepancies
        ) {

            Contract_Discrepancy__c discrepancy =
                new Contract_Discrepancy__c(
                    Contract_Review__c = review.Id,
                    Field__c = comparison.field,
                    Salesforce_Source__c = comparison.salesforceSource,
                    Salesforce_Value__c = comparison.salesforceValue,
                    Contract_Value__c = comparison.contractValue,
                    Status__c = comparison.status,
                    Severity__c = comparison.severity,
                    Confidence__c = comparison.confidence,
                    Contract_Evidence__c = comparison.contractEvidence,
                    Explanation__c = comparison.explanation
                );

            recordsToInsert.add(discrepancy);
        }

        if (!recordsToInsert.isEmpty()) {
            insert recordsToInsert;
        }

        return review.Id;
    }


    private static List<ContractAnalysisResult.Comparison>
        getDiscrepancies(ContractAnalysisResult result) {

        List<ContractAnalysisResult.Comparison> discrepancies =
            new List<ContractAnalysisResult.Comparison>();

        for (
            ContractAnalysisResult.Comparison comparison :
            result.comparisons
        ) {

            if (
                DISCREPANCY_STATUSES.contains(
                    comparison.status
                )
            ) {
                discrepancies.add(comparison);
            }
        }

        return discrepancies;
    }


    private static String determineOverallResult(
        ContractAnalysisResult result
    ) {

        Boolean hasMismatch = false;
        Boolean requiresReview = false;

        for (
            ContractAnalysisResult.Comparison comparison :
            result.comparisons
        ) {
            if (comparison.status == 'MISMATCH') {
                hasMismatch = true;
            }

            if (
                comparison.status == 'UNKNOWN' ||
                comparison.status == 'AMBIGUOUS'
            ) {
                requiresReview = true;
            }
        }

        if (hasMismatch) {
            return 'MISMATCH';
        }

        if (requiresReview) {
            return 'REVIEW_REQUIRED';
        }

        return 'MATCH';
    }


    private static void validateInput(
        ContractContext context,
        ContractAnalysisResult result
    ) {

        if (context == null) {
            throw new ContractReviewException(
                'Contract context cannot be null.'
            );
        }

        if (context.opportunityId == null) {
            throw new ContractReviewException(
                'Opportunity Id cannot be null.'
            );
        }

        if (context.contractId == null) {
            throw new ContractReviewException(
                'Contract Id cannot be null.'
            );
        }

        if (result == null) {
            throw new ContractReviewException(
                'Contract analysis result cannot be null.'
            );
        }

        if (result.comparisons == null) {
            throw new ContractReviewException(
                'Contract analysis result does not contain comparisons.'
            );
        }
    }


    public class ContractReviewException extends Exception {}
}