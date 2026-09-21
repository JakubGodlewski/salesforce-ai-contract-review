import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getLatestReview from '@salesforce/apex/ContractReviewPanelController.getLatestReview';

const FIELD_LABELS = {
    amount: 'Amount',
    discount: 'Discount',
    noticePeriodDays: 'Notice Period',
    paymentTerms: 'Payment Terms',
    accountName: 'Account',
    contractStartDate: 'Contract Start Date',
    contractEndDate: 'Contract End Date',
    contractTermMonths: 'Contract Term'
};

const SEVERITY_ICONS = {
    HIGH: '●',
    MEDIUM: '●',
    LOW: '●',
    NONE: '●'
};

const SEVERITY_ORDER = {
    HIGH: 1,
    MEDIUM: 2,
    LOW: 3,
    NONE: 4
};

export default class ContractReviewPanel extends NavigationMixin(LightningElement) {
    @api recordId;
    review;
    errorMessage;
    isLoading = true;

    @wire(getLatestReview, { opportunityId: '$recordId' })
    wiredReview({ data, error }) {
        this.isLoading = false;
        if (data) {
            this.review = data;
            this.errorMessage = undefined;
        } else if (error) {
            this.review = undefined;
            this.errorMessage = this.reduceError(error);
        }
    }

    get hasReview() {
        return Boolean(this.review);
    }

    get discrepancies() {
        return (this.review?.discrepancies || []).map((item) => ({
            ...item,
            fieldLabel: FIELD_LABELS[item.field] || item.field,
            severityClass: `severity severity-${(item.severity || 'NONE').toLowerCase()}`,
            severityIcon: SEVERITY_ICONS[item.severity] || SEVERITY_ICONS.NONE,
            confidenceLabel: this.formatConfidence(item.confidence)
        })).sort((left, right) => {
            const leftOrder = SEVERITY_ORDER[left.severity] || SEVERITY_ORDER.NONE;
            const rightOrder = SEVERITY_ORDER[right.severity] || SEVERITY_ORDER.NONE;
            return leftOrder - rightOrder || left.fieldLabel.localeCompare(right.fieldLabel);
        });
    }

    get formattedAnalysisDate() {
        if (!this.review?.analysisDate) {
            return 'date unavailable';
        }
        return new Intl.DateTimeFormat('en-US', {
            month: 'short',
            day: 'numeric',
            year: 'numeric'
        }).format(new Date(this.review.analysisDate));
    }

    get resultBadgeClass() {
        return `result-badge result-${(this.review?.overallResult || 'UNKNOWN').toLowerCase()}`;
    }

    get resultIcon() {
        return this.review?.overallResult === 'MATCH' ? '✓' : '⚠';
    }

    formatConfidence(confidence) {
        if (confidence === null || confidence === undefined) {
            return 'AI confidence unavailable';
        }
        return `AI confidence: ${Math.round(confidence * 100)}%`;
    }

    handleViewReview() {
        if (!this.review?.id) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.review.id,
                objectApiName: 'Contract_Review__c',
                actionName: 'view'
            }
        });
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.body?.message || error?.message || 'Unable to load the latest contract review.';
    }
}
