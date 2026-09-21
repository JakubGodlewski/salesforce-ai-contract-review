public with sharing class ContractReviewPanelController {

    @AuraEnabled(cacheable=true)
    public static ReviewViewModel getLatestReview(Id opportunityId) {
        if (opportunityId == null) {
            throw new AuraHandledException('Opportunity Id is required.');
        }

        List<Contract_Review__c> reviews = [
            SELECT Id,
                Analysis_Date__c,
                Model__c,
                Overall_Result__c,
                Discrepancy_Count__c,
                Summary__c,
                (SELECT Id,
                    Field__c,
                    Salesforce_Source__c,
                    Salesforce_Value__c,
                    Contract_Value__c,
                    Status__c,
                    Severity__c,
                    Confidence__c,
                    Contract_Evidence__c,
                    Explanation__c
                 FROM Contract_Discrepancies__r
                 ORDER BY Severity__c ASC, Field__c ASC)
            FROM Contract_Review__c
            WHERE Opportunity__c = :opportunityId
            ORDER BY Analysis_Date__c DESC NULLS LAST, CreatedDate DESC
            LIMIT 1
        ];

        if (reviews.isEmpty()) {
            return null;
        }

        Contract_Review__c review = reviews[0];
        ReviewViewModel viewModel = new ReviewViewModel();
        viewModel.id = review.Id;
        viewModel.analysisDate = review.Analysis_Date__c;
        viewModel.model = review.Model__c;
        viewModel.overallResult = review.Overall_Result__c;
        viewModel.discrepancyCount = review.Discrepancy_Count__c == null
            ? 0
            : Integer.valueOf(review.Discrepancy_Count__c);
        viewModel.summary = review.Summary__c;
        viewModel.discrepancies = new List<DiscrepancyViewModel>();

        for (Contract_Discrepancy__c discrepancy : review.Contract_Discrepancies__r) {
            DiscrepancyViewModel discrepancyViewModel = new DiscrepancyViewModel();
            discrepancyViewModel.id = discrepancy.Id;
            discrepancyViewModel.field = discrepancy.Field__c;
            discrepancyViewModel.salesforceSource = discrepancy.Salesforce_Source__c;
            discrepancyViewModel.salesforceValue = discrepancy.Salesforce_Value__c;
            discrepancyViewModel.contractValue = discrepancy.Contract_Value__c;
            discrepancyViewModel.status = discrepancy.Status__c;
            discrepancyViewModel.severity = discrepancy.Severity__c;
            discrepancyViewModel.confidence = discrepancy.Confidence__c;
            discrepancyViewModel.contractEvidence = discrepancy.Contract_Evidence__c;
            discrepancyViewModel.explanation = discrepancy.Explanation__c;
            viewModel.discrepancies.add(discrepancyViewModel);
        }

        return viewModel;
    }

    public class ReviewViewModel {
        @AuraEnabled public Id id;
        @AuraEnabled public Datetime analysisDate;
        @AuraEnabled public String model;
        @AuraEnabled public String overallResult;
        @AuraEnabled public Integer discrepancyCount;
        @AuraEnabled public String summary;
        @AuraEnabled public List<DiscrepancyViewModel> discrepancies;
    }

    public class DiscrepancyViewModel {
        @AuraEnabled public Id id;
        @AuraEnabled public String field;
        @AuraEnabled public String salesforceSource;
        @AuraEnabled public String salesforceValue;
        @AuraEnabled public String contractValue;
        @AuraEnabled public String status;
        @AuraEnabled public String severity;
        @AuraEnabled public Decimal confidence;
        @AuraEnabled public String contractEvidence;
        @AuraEnabled public String explanation;
    }
}
