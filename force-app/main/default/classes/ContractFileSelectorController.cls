public with sharing class ContractFileSelectorController {

    @AuraEnabled(cacheable=true)
    public static List<ContractFileService.PdfOption> getAvailablePdfs(
        Id opportunityId
    ) {
        if (opportunityId == null) {
            throw new AuraHandledException('Opportunity Id is required.');
        }

        Opportunity opportunity = [
            SELECT ContractId
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];
        if (opportunity.ContractId == null) {
            return new List<ContractFileService.PdfOption>();
        }

        return ContractFileService.getAvailablePdfs(opportunity.ContractId);
    }
}
