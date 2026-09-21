import { LightningElement, api, wire } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import getAvailablePdfs from '@salesforce/apex/ContractFileSelectorController.getAvailablePdfs';

export default class ContractPdfSelector extends LightningElement {
    @api recordId;
    @api selectedContentVersionId;
    @api selectedDocumentId;
    options = [];
    errorMessage;
    isLoading = true;

    @wire(getAvailablePdfs, { opportunityId: '$recordId' })
    wiredPdfs({ data, error }) {
        this.isLoading = false;
        if (data) {
            this.options = data.map((pdf) => ({
                label: `${pdf.title} (${this.formatDate(pdf.createdDate)})`,
                value: pdf.contentVersionId,
                documentId: pdf.documentId
            }));
            this.errorMessage = undefined;
            if (!this.selectedContentVersionId && this.options.length === 1) {
                this.updateSelection(this.options[0].value);
            }
        } else if (error) {
            this.options = [];
            this.errorMessage = this.reduceError(error);
        }
    }

    handleChange(event) {
        this.updateSelection(event.detail.value);
    }

    get hasOptions() {
        return this.options.length > 0;
    }

    updateSelection(value) {
        this.selectedContentVersionId = value;
        const selectedOption = this.options.find((option) => option.value === value);
        this.selectedDocumentId = selectedOption?.documentId;
        this.dispatchEvent(new FlowAttributeChangeEvent('selectedContentVersionId', value));
        this.dispatchEvent(new FlowAttributeChangeEvent('selectedDocumentId', this.selectedDocumentId));
    }

    formatDate(value) {
        return value
            ? new Intl.DateTimeFormat('en-US', { dateStyle: 'medium' }).format(new Date(value))
            : 'date unavailable';
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.body?.message || error?.message || 'Unable to load contract PDFs.';
    }
}
