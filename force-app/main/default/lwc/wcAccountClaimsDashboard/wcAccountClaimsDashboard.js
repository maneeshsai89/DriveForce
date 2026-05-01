import { LightningElement, api, wire } from 'lwc';
import getClaimMetricsByAccount from '@salesforce/apex/WC_AccountClaimsDashboardController.getClaimMetricsByAccount';

export default class WcAccountClaimsDashboard extends LightningElement {
    /** Explicit Account Id (e.g. from App/Home page designer property or a parent component). */
    @api accountId;

    /** Populated automatically on Account record pages. */
    @api recordId;

    /** When true, renders metrics only (no card) for use inside a parent layout. */
    @api embedded = false;

    get resolvedAccountId() {
        const id = this.accountId || this.recordId;
        return id ? id : undefined;
    }

    @wire(getClaimMetricsByAccount, { accountId: '$resolvedAccountId' })
    metrics;

    get hasAccountContext() {
        return Boolean(this.resolvedAccountId);
    }

    get isLoading() {
        if (!this.hasAccountContext) {
            return false;
        }
        const w = this.metrics;
        return w === undefined || (w.data === undefined && w.error === undefined);
    }

    get loadError() {
        const err = this.metrics?.error;
        if (err) {
            return this.reduceError(err);
        }
        return undefined;
    }

    get m() {
        return this.metrics?.data;
    }

    get totalRaised() {
        return this.m ? this.m.totalRaised : 0;
    }

    get pendingCount() {
        return this.m ? this.m.pendingCount : 0;
    }

    get approvedCount() {
        return this.m ? this.m.approvedCount : 0;
    }

    get rejectedCount() {
        return this.m ? this.m.rejectedCount : 0;
    }

    get claimsThisMonth() {
        return this.m && this.m.claimsThisMonth != null ? this.m.claimsThisMonth : 0;
    }

    get totalSubtext() {
        const n = this.claimsThisMonth;
        if (n === 0) {
            return 'No new claims this month';
        }
        return `+${n} this month`;
    }

    get pendingSubtext() {
        return 'Awaiting decision';
    }

    get approvedSubtext() {
        const t = this.totalRaised;
        if (!t) {
            return '—';
        }
        return `${Math.round((this.approvedCount / t) * 100)}% approval rate`;
    }

    get rejectedSubtext() {
        return 'Closed without approval';
    }

    reduceError(err) {
        if (Array.isArray(err.body)) {
            return err.body.map((e) => e.message).join(', ');
        }
        if (typeof err.body?.message === 'string') {
            return err.body.message;
        }
        if (typeof err.message === 'string') {
            return err.message;
        }
        return 'Unknown error';
    }
}