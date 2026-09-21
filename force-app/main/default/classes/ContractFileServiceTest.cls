@IsTest
private class ContractFileServiceTest {

    @IsTest
    static void returnsPdfLinkedToContract() {
        Account account = ContractAnalysisTestDataFactory.createAccount();
        Contract contract = ContractAnalysisTestDataFactory.createContract(account.Id);
        ContentVersion expected = ContractAnalysisTestDataFactory.createPdfVersion(
            contract.Id,
            'Primary Contract',
            'primary-contract.pdf',
            'PDF test content'
        );

        Test.startTest();
        ContentVersion actual = ContractFileService.getLatestPdf(contract.Id);
        Test.stopTest();

        Assert.areEqual(expected.Id, actual.Id);
        Assert.areEqual('PDF', actual.FileType);
        Assert.areEqual(expected.ContentDocumentId, actual.ContentDocumentId);
    }

    @IsTest
    static void selectsLatestPdfAndIgnoresTextFile() {
        Account account = ContractAnalysisTestDataFactory.createAccount();
        Contract contract = ContractAnalysisTestDataFactory.createContract(account.Id);
        ContentVersion oldPdf = ContractAnalysisTestDataFactory.createPdfVersion(
            contract.Id,
            'Old Contract',
            'old-contract.pdf',
            'Old PDF'
        );
        Test.setCreatedDate(oldPdf.Id, DateTime.now().addDays(-2));
        ContentVersion textVersion = ContractAnalysisTestDataFactory.createPdfVersion(
            contract.Id,
            'Notes',
            'notes.txt',
            'Not a PDF'
        );
        ContentVersion latestPdf = ContractAnalysisTestDataFactory.createPdfVersion(
            contract.Id,
            'Latest Contract',
            'latest-contract.pdf',
            'Latest PDF'
        );

        Test.startTest();
        ContentVersion actual = ContractFileService.getLatestPdf(contract.Id);
        Test.stopTest();

        Assert.areEqual(latestPdf.Id, actual.Id);
        Assert.areNotEqual(textVersion.Id, actual.Id);
        Assert.areEqual('PDF', actual.FileType);
    }

    @IsTest
    static void returnsExplicitlySelectedPdf() {
        Account account = ContractAnalysisTestDataFactory.createAccount();
        Contract contract = ContractAnalysisTestDataFactory.createContract(account.Id);
        ContentVersion firstPdf = ContractAnalysisTestDataFactory.createPdfVersion(
            contract.Id,
            'First Contract',
            'first-contract.pdf',
            'First PDF'
        );
        ContentVersion selectedPdf = ContractAnalysisTestDataFactory.createPdfVersion(
            contract.Id,
            'Selected Contract',
            'selected-contract.pdf',
            'Selected PDF'
        );

        Test.startTest();
        ContentVersion actual = ContractFileService.getPdfVersion(
            contract.Id,
            firstPdf.Id
        );
        Test.stopTest();

        Assert.areEqual(firstPdf.Id, actual.Id);
        Assert.areNotEqual(selectedPdf.Id, actual.Id);
        Assert.areEqual('PDF', actual.FileType);
    }

    @IsTest
    static void rejectsSelectedPdfFromAnotherContract() {
        Account account = ContractAnalysisTestDataFactory.createAccount();
        Contract firstContract = ContractAnalysisTestDataFactory.createContract(account.Id);
        Contract secondContract = ContractAnalysisTestDataFactory.createContract(account.Id);
        ContentVersion selectedPdf = ContractAnalysisTestDataFactory.createPdfVersion(
            secondContract.Id,
            'Other Contract',
            'other-contract.pdf',
            'Other PDF'
        );

        try {
            ContractFileService.getPdfVersion(firstContract.Id, selectedPdf.Id);
            Assert.fail('Expected ContractFileException.');
        } catch (ContractFileService.ContractFileException caughtException) {
            Assert.isTrue(
                caughtException.getMessage().contains('not found on the related Contract')
            );
        }
    }

    @IsTest
    static void throwsWhenContractHasNoFiles() {
        Account account = ContractAnalysisTestDataFactory.createAccount();
        Contract contract = ContractAnalysisTestDataFactory.createContract(account.Id);

        try {
            ContractFileService.getLatestPdf(contract.Id);
            Assert.fail('Expected ContractFileException.');
        } catch (ContractFileService.ContractFileException caughtException) {
            Assert.isTrue(caughtException.getMessage().contains('No files found'));
        }
    }

    @IsTest
    static void throwsWhenContractHasNoPdf() {
        Account account = ContractAnalysisTestDataFactory.createAccount();
        Contract contract = ContractAnalysisTestDataFactory.createContract(account.Id);
        ContractAnalysisTestDataFactory.createPdfVersion(
            contract.Id,
            'Notes',
            'notes.txt',
            'Not a PDF'
        );

        try {
            ContractFileService.getLatestPdf(contract.Id);
            Assert.fail('Expected ContractFileException.');
        } catch (ContractFileService.ContractFileException caughtException) {
            Assert.isTrue(caughtException.getMessage().contains('No PDF found'));
        }
    }
}
