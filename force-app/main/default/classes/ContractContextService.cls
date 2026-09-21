public with sharing class ContractContextService {

    public static ContractContext getContext(Id opportunityId) {

        if (opportunityId == null) {
            throw new ContractContextException(
                'Opportunity Id cannot be null.'
            );
        }

        Opportunity opp = [
            SELECT
                Id,
                Name,
                Account.Name,
                Amount,
                Discount__c,
                Payment_Terms__c,
                Notice_Period_Days__c,
                ContractId,
                Contract.StartDate,
                Contract.EndDate,
                Contract.ContractTerm
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];

        if (opp.Contract == null) {
            throw new ContractContextException(
                'Opportunity does not have a Contract assigned.'
            );
        }

        ContractContext context = new ContractContext();

        context.opportunityId = opp.Id;
        context.opportunityName = opp.Name;
        context.accountName = opp.Account?.Name;

        context.amount = opp.Amount;
        context.discount = opp.Discount__c;
        context.paymentTerms = opp.Payment_Terms__c;
        context.noticePeriodDays =
            opp.Notice_Period_Days__c != null
            ? Integer.valueOf(opp.Notice_Period_Days__c)
            : null;

        context.contractId = opp.ContractId;
        context.contractStartDate = opp.Contract.StartDate;
        context.contractEndDate = opp.Contract.EndDate;
        context.contractTermMonths =
            opp.Contract.ContractTerm;

        return context;
    }

    public class ContractContextException extends Exception {}
}