public with sharing class ContractFileService {

    public class PdfOption {
        @AuraEnabled public Id contentVersionId;
        @AuraEnabled public Id documentId;
        @AuraEnabled public String title;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public Integer contentSize;
    }

    public static ContentVersion getLatestPdf(Id contractId) {

        if (contractId == null) {
            throw new ContractFileException(
                'Contract Id cannot be null.'
            );
        }

        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :contractId
        ];

        if (links.isEmpty()) {
            throw new ContractFileException(
                'No files found for Contract: ' + contractId
            );
        }

        Set<Id> documentIds = new Set<Id>();

        for (ContentDocumentLink link : links) {
            documentIds.add(link.ContentDocumentId);
        }

        List<ContentVersion> pdfVersions = [
            SELECT
                Id,
                Title,
                FileExtension,
                FileType,
                ContentDocumentId,
                VersionData,
                ContentSize,
                CreatedDate
            FROM ContentVersion
            WHERE ContentDocumentId IN :documentIds
            AND IsLatest = true
            AND FileType = 'PDF'
            ORDER BY CreatedDate DESC
        ];

        if (pdfVersions.isEmpty()) {
            throw new ContractFileException(
                'No PDF found for Contract: ' + contractId
            );
        }

        return pdfVersions[0];
    }

    public static ContentVersion getPdf(Id contractId, Id contentDocumentId) {
        if (contentDocumentId == null) {
            return getLatestPdf(contractId);
        }

        List<ContentVersion> versions = [
            SELECT Id
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId
            AND IsLatest = true
            AND FileType = 'PDF'
            LIMIT 1
        ];
        if (versions.isEmpty()) {
            throw new ContractFileException(
                'Selected PDF was not found on the related Contract.'
            );
        }
        return getPdfVersion(contractId, versions[0].Id);
    }

    public static ContentVersion getPdfVersion(
        Id contractId,
        Id contentVersionId
    ) {
        if (contentVersionId == null) {
            return getLatestPdf(contractId);
        }

        if (contractId == null) {
            throw new ContractFileException(
                'Contract Id cannot be null.'
            );
        }

        ContentVersion selectedVersion = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :contentVersionId
            AND IsLatest = true
            AND FileType = 'PDF'
            LIMIT 1
        ];

        List<ContentDocumentLink> selectedLinks = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :contractId
            AND ContentDocumentId = :selectedVersion.ContentDocumentId
            LIMIT 1
        ];
        if (selectedLinks.isEmpty()) {
            throw new ContractFileException(
                'Selected PDF was not found on the related Contract.'
            );
        }

        List<ContentVersion> pdfVersions = [
            SELECT
                Id,
                Title,
                FileExtension,
                FileType,
                ContentDocumentId,
                VersionData,
                ContentSize,
                CreatedDate
            FROM ContentVersion
            WHERE Id = :contentVersionId
            AND IsLatest = true
            AND FileType = 'PDF'
            LIMIT 1
        ];

        if (pdfVersions.isEmpty()) {
            throw new ContractFileException(
                'Selected PDF was not found on the related Contract.'
            );
        }

        return pdfVersions[0];
    }

    public static List<PdfOption> getAvailablePdfs(Id contractId) {
        List<PdfOption> options = new List<PdfOption>();
        if (contractId == null) {
            return options;
        }

        Set<Id> documentIds = new Set<Id>();
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :contractId
        ]) {
            documentIds.add(link.ContentDocumentId);
        }

        for (ContentVersion version : [
            SELECT Id, ContentDocumentId, Title, CreatedDate, ContentSize
            FROM ContentVersion
            WHERE IsLatest = true
            AND FileType = 'PDF'
            AND ContentDocumentId IN :documentIds
            ORDER BY CreatedDate DESC
        ]) {
            PdfOption option = new PdfOption();
            option.contentVersionId = version.Id;
            option.documentId = version.ContentDocumentId;
            option.title = version.Title;
            option.createdDate = version.CreatedDate;
            option.contentSize = version.ContentSize;
            options.add(option);
        }
        return options;
    }

    public class ContractFileException extends Exception {}
}