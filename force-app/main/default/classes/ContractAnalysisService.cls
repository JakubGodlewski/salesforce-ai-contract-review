public with sharing class ContractAnalysisService {

    private static final Set<String> ALLOWED_COMPARISON_STATUSES =
        new Set<String>{
            'MATCH',
            'MISMATCH',
            'UNKNOWN',
            'AMBIGUOUS'
        };

    private static final Set<String> ALLOWED_SEVERITIES =
        new Set<String>{
            'NONE',
            'LOW',
            'MEDIUM',
            'HIGH'
        };

    /**
     * Runs the complete contract analysis process.
     *
     * Opportunity
     *   -> Contract Context
     *   -> Contract PDF
     *   -> Claude
     *   -> Validation
     *   -> ContractAnalysisResult
     */
    public static AnalysisOutcome analyze(Id opportunityId) {
        return analyze(opportunityId, null);
    }

    public static AnalysisOutcome analyze(
        Id opportunityId,
        Id contentVersionId
    ) {

        if (opportunityId == null) {
            throw new ContractAnalysisException(
                'Opportunity Id cannot be null.'
            );
        }

        // 1. Get Salesforce data
        ContractContext context =
            ContractContextService.getContext(opportunityId);

        // 2. Get PDF attached to the related Contract
        ContentVersion pdf =
            ContractFileService.getPdfVersion(context.contractId, contentVersionId);

        if (pdf == null || pdf.VersionData == null) {
            throw new ContractAnalysisException(
                'Contract PDF could not be loaded.'
            );
        }

        // 3. Send Salesforce data + PDF to Claude
        ContractAnalysisResult result =
            ClaudeClient.analyzeContract(
                pdf.VersionData,
                context
            );

        // 4. Validate LLM response before using it
        validateResult(result);

        Id contractReviewId =
            ContractReviewService.saveReview(
                context,
                result
            );

        return new AnalysisOutcome(
            result,
            contractReviewId
        );
    }

    /**
     * Validates the structure and values returned by the LLM.
     *
     * We never assume that an LLM response is valid just because
     * it was successfully deserialized.
     */
    private static void validateResult(
        ContractAnalysisResult result
    ) {

        if (result == null) {
            throw new ContractAnalysisException(
                'Claude returned no analysis result.'
            );
        }

        if (result.comparisons == null) {
            throw new ContractAnalysisException(
                'Analysis result does not contain comparisons.'
            );
        }

        for (
            ContractAnalysisResult.Comparison comparison :
            result.comparisons
        ) {
            validateComparison(comparison);
        }

        result.overallStatus = determineOverallStatus(result.comparisons);
    }

    private static String determineOverallStatus(
        List<ContractAnalysisResult.Comparison> comparisons
    ) {

        Boolean hasMismatch = false;
        Boolean requiresReview = false;

        for (
            ContractAnalysisResult.Comparison comparison :
            comparisons
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

    /**
     * Validates a single comparison returned by Claude.
     */
    private static void validateComparison(
        ContractAnalysisResult.Comparison comparison
    ) {

        if (comparison == null) {
            throw new ContractAnalysisException(
                'Analysis contains an empty comparison.'
            );
        }

        if (String.isBlank(comparison.field)) {
            throw new ContractAnalysisException(
                'Comparison does not contain a field name.'
            );
        }

        if (String.isBlank(comparison.status)) {
            throw new ContractAnalysisException(
                'Comparison for "' +
                comparison.field +
                '" does not contain a status.'
            );
        }

        if (!ALLOWED_COMPARISON_STATUSES.contains(
            comparison.status
        )) {
            throw new ContractAnalysisException(
                'Invalid status "' +
                comparison.status +
                '" for field "' +
                comparison.field +
                '".'
            );
        }

        if (
            String.isNotBlank(comparison.severity) &&
            !ALLOWED_SEVERITIES.contains(comparison.severity)
        ) {
            throw new ContractAnalysisException(
                'Invalid severity "' +
                comparison.severity +
                '" for field "' +
                comparison.field +
                '".'
            );
        }

        if (
            comparison.confidence != null &&
            (
                comparison.confidence < 0 ||
                comparison.confidence > 1
            )
        ) {
            throw new ContractAnalysisException(
                'Confidence must be between 0 and 1 for field "' +
                comparison.field +
                '".'
            );
        }
    }

    public class AnalysisOutcome {
        public ContractAnalysisResult result;
        public Id contractReviewId;

        public AnalysisOutcome(
            ContractAnalysisResult result,
            Id contractReviewId
        ) {
            this.result = result;
            this.contractReviewId = contractReviewId;
        }
    }

    public class ContractAnalysisException extends Exception {}
}