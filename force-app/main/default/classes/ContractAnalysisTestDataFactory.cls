@IsTest
public class ContractAnalysisTestDataFactory {

    public class Scenario {
        public Account account;
        public Opportunity opportunity;
        public Contract contract;
        public ContentVersion contentVersion;
        public ContentDocumentLink contentDocumentLink;
    }

    public static Account createAccount() {
        return createAccount('Acme Sp. z o.o.');
    }

    public static Account createAccount(String accountName) {
        Account account = new Account(Name = accountName);
        insert account;
        return account;
    }

    public static Account createAccount(String accountName, Id ownerId) {
        Account account = new Account(Name = accountName, OwnerId = ownerId);
        insert account;
        return account;
    }

    public static void createTestUsersAndData() {
        Profile profile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];
        Long suffix = DateTime.now().getTime();
        User user = createUser(
            profile.Id,
            'contract-analysis-user-' + suffix + '@example.test',
            'Contract Analysis User',
            'cautest'
        );
        User admin = createUser(
            profile.Id,
            'contract-analysis-admin-' + suffix + '@example.test',
            'Contract Analysis Admin',
            'caitest'
        );

        System.runAs(new User(Id = UserInfo.getUserId())) {
            createCompleteScenario(user.Id);
            createCompleteScenario(admin.Id);
        }

        PermissionSet userPermissionSet = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = 'Contract_Analysis_AI_User'
            LIMIT 1
        ];
        PermissionSet adminPermissionSet = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = 'Contract_Analysis_AI_Admin'
            LIMIT 1
        ];
        assignPermissionSetsAsync(
            user.Id,
            admin.Id,
            userPermissionSet.Id,
            adminPermissionSet.Id
        );
        Test.startTest();
        Test.stopTest();

    }

    @future
    private static void assignPermissionSetsAsync(
        Id userId,
        Id adminId,
        Id userPermissionSetId,
        Id adminPermissionSetId
    ) {
        insert new List<PermissionSetAssignment>{
            new PermissionSetAssignment(
                AssigneeId = userId,
                PermissionSetId = userPermissionSetId
            ),
            new PermissionSetAssignment(
                AssigneeId = adminId,
                PermissionSetId = adminPermissionSetId
            )
        };
    }

    public static Scenario getScenarioForOwner(Id ownerId) {
        Opportunity opportunity = [
            SELECT Id, ContractId
            FROM Opportunity
            WHERE OwnerId = :ownerId
            AND Name = 'AI Contract Analysis Test Opportunity'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        Contract contract = [
            SELECT Id
            FROM Contract
            WHERE Id = :opportunity.ContractId
        ];
        ContentDocumentLink link = [
            SELECT Id, ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :contract.Id
            LIMIT 1
        ];
        ContentVersion version = [
            SELECT Id, ContentDocumentId, VersionData, FileType
            FROM ContentVersion
            WHERE ContentDocumentId = :link.ContentDocumentId
            AND IsLatest = true
            LIMIT 1
        ];

        Scenario scenario = new Scenario();
        scenario.opportunity = opportunity;
        scenario.contract = contract;
        scenario.contentVersion = version;
        scenario.contentDocumentLink = link;
        return scenario;
    }

    public static User getTestUser(Boolean admin) {
        String lastName = admin
            ? 'Contract Analysis Admin'
            : 'Contract Analysis User';
        return [
            SELECT Id, LastName
            FROM User
            WHERE LastName = :lastName
            LIMIT 1
        ];
    }

    private static User createUser(
        Id profileId,
        String username,
        String lastName,
        String alias
    ) {
        User user = new User(
            Alias = alias,
            Email = username,
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LastName = lastName,
            LocaleSidKey = 'en_US',
            ProfileId = profileId,
            TimeZoneSidKey = 'Europe/Warsaw',
            Username = username
        );
        insert user;
        return user;
    }

    public static Contract createContract(Id accountId) {
        return createContract(
            accountId,
            Date.newInstance(2026, 11, 1),
            Date.newInstance(2027, 10, 31),
            12
        );
    }

    public static Contract createContract(
        Id accountId,
        Date startDate,
        Date endDate,
        Integer termMonths
    ) {
        Contract contract = new Contract(
            AccountId = accountId,
            StartDate = startDate,
            ContractTerm = termMonths,
            Status = 'Draft'
        );
        insert contract;
        return contract;
    }

    public static Contract createContract(
        Id accountId,
        Date startDate,
        Integer termMonths,
        Id ownerId
    ) {
        Contract contract = new Contract(
            AccountId = accountId,
            StartDate = startDate,
            ContractTerm = termMonths,
            Status = 'Draft',
            OwnerId = ownerId
        );
        insert contract;
        return contract;
    }

    public static Opportunity createOpportunity(
        Id accountId,
        Id contractId
    ) {
        return createOpportunity(
            accountId,
            contractId,
            120000,
            10,
            'Net 30',
            60
        );
    }

    public static Opportunity createOpportunity(
        Id accountId,
        Id contractId,
        Decimal amount,
        Decimal discount,
        String paymentTerms,
        Integer noticePeriodDays
    ) {
        Opportunity opportunity = new Opportunity(
            Name = 'AI Contract Analysis Test Opportunity',
            AccountId = accountId,
            StageName = 'Prospecting',
            CloseDate = Date.newInstance(2026, 12, 31),
            Amount = amount,
            Discount__c = discount,
            Payment_Terms__c = paymentTerms,
            Notice_Period_Days__c = noticePeriodDays,
            ContractId = contractId
        );
        insert opportunity;
        return opportunity;
    }

    public static Opportunity createOpportunity(
        Id accountId,
        Id contractId,
        Decimal amount,
        Decimal discount,
        String paymentTerms,
        Integer noticePeriodDays,
        Id ownerId
    ) {
        Opportunity opportunity = new Opportunity(
            Name = 'AI Contract Analysis Test Opportunity',
            AccountId = accountId,
            StageName = 'Prospecting',
            CloseDate = Date.newInstance(2026, 12, 31),
            Amount = amount,
            Discount__c = discount,
            Payment_Terms__c = paymentTerms,
            Notice_Period_Days__c = noticePeriodDays,
            ContractId = contractId,
            OwnerId = ownerId
        );
        insert opportunity;
        return opportunity;
    }

    public static ContentVersion createPdfVersion(
        Id contractId,
        String title,
        String pathOnClient,
        String contents
    ) {
        ContentVersion version = new ContentVersion(
            Title = title,
            PathOnClient = pathOnClient,
            VersionData = Blob.valueOf(contents),
            FirstPublishLocationId = contractId,
            IsMajorVersion = true
        );
        insert version;
        return [
            SELECT Id, ContentDocumentId, VersionData, FileType
            FROM ContentVersion
            WHERE Id = :version.Id
        ];
    }

    public static Scenario createCompleteScenario() {
        Account account = createAccount();
        Contract contract = createContract(account.Id);
        Opportunity opportunity = createOpportunity(account.Id, contract.Id);
        ContentVersion version = createPdfVersion(
            contract.Id,
            'Contract Analysis Test PDF',
            'contract-analysis-test.pdf',
            'Contract amount: 115000. Discount: 15%. Notice period: 30 days.'
        );
        ContentDocumentLink link = [
            SELECT Id, ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :version.ContentDocumentId
            AND LinkedEntityId = :contract.Id
            LIMIT 1
        ];

        Scenario scenario = new Scenario();
        scenario.account = account;
        scenario.contract = contract;
        scenario.opportunity = opportunity;
        scenario.contentVersion = version;
        scenario.contentDocumentLink = link;
        return scenario;
    }

    public static Scenario createCompleteScenario(Id ownerId) {
        Account account = createAccount('Acme Sp. z o.o.', ownerId);
        Contract contract = createContract(
            account.Id,
            Date.newInstance(2026, 11, 1),
            12,
            ownerId
        );
        Opportunity opportunity = createOpportunity(
            account.Id,
            contract.Id,
            120000,
            10,
            'Net 30',
            60,
            ownerId
        );
        ContentVersion version = createPdfVersion(
            contract.Id,
            'Contract Analysis Test PDF',
            'contract-analysis-test.pdf',
            'Contract amount: 115000. Discount: 15%. Notice period: 30 days.'
        );
        ContentDocumentLink link = [
            SELECT Id, ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :version.ContentDocumentId
            AND LinkedEntityId = :contract.Id
            LIMIT 1
        ];

        Scenario scenario = new Scenario();
        scenario.account = account;
        scenario.contract = contract;
        scenario.opportunity = opportunity;
        scenario.contentVersion = version;
        scenario.contentDocumentLink = link;
        return scenario;
    }

}
