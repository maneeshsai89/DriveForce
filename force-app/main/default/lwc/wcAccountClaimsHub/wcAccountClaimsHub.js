import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import NAME_FIELD from '@salesforce/schema/Account.Name';
import getClaimMetricsByAccount from '@salesforce/apex/WC_AccountClaimsDashboardController.getClaimMetricsByAccount';
import USER_ID from '@salesforce/user/Id';
import USER_CONTACT_ID_FIELD from '@salesforce/schema/User.ContactId';
import CONTACT_ACCOUNT_ID_FIELD from '@salesforce/schema/Contact.AccountId';
import DEALER_HERO_IMAGE from '@salesforce/resourceUrl/dealerPortalHero';
import DEALER_INSIGHT_IMAGE from '@salesforce/resourceUrl/dealerClaimInsight';

const ACCOUNT_FIELDS = [NAME_FIELD];
const USER_FIELDS = [USER_CONTACT_ID_FIELD];
const CONTACT_FIELDS = [CONTACT_ACCOUNT_ID_FIELD];

export default class WcAccountClaimsHub extends LightningElement {
    @api accountId;
    @api recordId;

    selectedClaim = null;
    _syncStart = Date.now();

    get resolvedAccountId() {
        return this.accountId || this.recordId || this.loggedInAccountId || undefined;
    }

    @wire(getClaimMetricsByAccount, { accountId: '$resolvedAccountId' })
    metrics;

    @wire(getRecord, { recordId: '$resolvedAccountId', fields: ACCOUNT_FIELDS })
    wiredAccount;

    @wire(getRecord, { recordId: USER_ID, fields: USER_FIELDS })
    wiredUser;

    @wire(getRecord, { recordId: '$loggedInContactId', fields: CONTACT_FIELDS })
    wiredContact;

    get hasContext() {
        return Boolean(this.resolvedAccountId);
    }

    get loggedInContactId() {
        return getFieldValue(this.wiredUser?.data, USER_CONTACT_ID_FIELD);
    }

    get loggedInAccountId() {
        return getFieldValue(this.wiredContact?.data, CONTACT_ACCOUNT_ID_FIELD);
    }

    get metricError() {
        const err = this.metrics?.error;
        if (!err) {
            return undefined;
        }
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

    get metricData() {
        return this.metrics?.data;
    }

    get totalRaised() {
        return this.metricData?.totalRaised ?? 0;
    }

    get pendingCount() {
        return this.metricData?.pendingCount ?? 0;
    }

    get approvedCount() {
        return this.metricData?.approvedCount ?? 0;
    }

    get rejectedCount() {
        return this.metricData?.rejectedCount ?? 0;
    }

    get claimsThisMonth() {
        return this.metricData?.claimsThisMonth ?? 0;
    }

    get totalSubtext() {
        return this.claimsThisMonth ? `+${this.claimsThisMonth} this month` : 'No new claims this month';
    }

    get pendingSubtext() {
        return 'Awaiting decision';
    }

    get approvedSubtext() {
        if (!this.totalRaised) {
            return '—';
        }
        return `${Math.round((this.approvedCount / this.totalRaised) * 100)}% approval rate`;
    }

    get rejectedSubtext() {
        return 'Closed without approval';
    }

    get accountName() {
        const d = this.wiredAccount?.data;
        if (!d) {
            return null;
        }
        return getFieldValue(d, NAME_FIELD);
    }

    get headerSubtitle() {
        const parts = [];
        if (this.accountName) {
            parts.push(this.accountName);
        }
        parts.push(`Last synced ${this.formatRelative(this._syncStart)}`);
        return parts.join(' · ');
    }

    formatRelative(startMs) {
        const mins = Math.floor((Date.now() - startMs) / 60000);
        if (mins < 1) {
            return 'moments ago';
        }
        if (mins === 1) {
            return '1 minute ago';
        }
        return `${mins} minutes ago`;
    }

    get claimBadgeClass() {
        const a = this.selectedClaim?.approvalResult;
        if (a === 'Approved') {
            return 'side-badge side-badge--ok';
        }
        if (a === 'Rejected') {
            return 'side-badge side-badge--bad';
        }
        return 'side-badge side-badge--pending';
    }

    get claimBadgeLabel() {
        const a = this.selectedClaim?.approvalResult;
        if (a === 'Pending') {
            return 'Under review';
        }
        return a || '—';
    }

    get claimMonogram() {
        const n = this.selectedClaim?.name;
        if (!n || n.length < 3) {
            return '···';
        }
        return n.slice(-3);
    }

    get selectedClaimUrl() {
        if (!this.selectedClaim?.id) {
            return '#';
        }
        return `/lightning/r/Claim/${this.selectedClaim.id}/view`;
    }

    get hasSelectedEstimate() {
        return this.selectedClaim != null && this.selectedClaim.estimatedAmount != null;
    }

    get dealerHeroImageUrl() {
        return DEALER_HERO_IMAGE;
    }

    get dealerInsightImageUrl() {
        return DEALER_INSIGHT_IMAGE;
    }

    formatApprovalTimestamp(dateLike) {
        if (!dateLike) {
            return null;
        }
        const d = new Date(dateLike);
        if (Number.isNaN(d.getTime())) {
            return null;
        }
        return new Intl.DateTimeFormat('en-US', {
            year: 'numeric',
            month: 'short',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit'
        }).format(d);
    }

    get timelineSteps() {
        const c = this.selectedClaim;
        if (!c) {
            return [];
        }
        const ap = c.approvalResult;
        const done = 'tl-dot tl-dot--done';
        const active = 'tl-dot tl-dot--active';
        const wait = 'tl-dot tl-dot--wait';
        const reviewDone = ap != null && ap !== '' && ap !== 'Pending';
        const decisionDone = ap === 'Approved' || ap === 'Rejected';
        const approvalWhen = this.formatApprovalTimestamp(c.approvedAt);
        const decisionSub = decisionDone
            ? (approvalWhen ? `${ap} · ${approvalWhen}` : ap)
            : 'Awaiting approval decision';
        return [
            {
                key: 'sub',
                label: 'Submitted',
                sub: 'Recorded in CRM',
                dotClass: done
            },
            {
                key: 'rev',
                label: 'Under review',
                sub: 'Awaiting approver',
                dotClass: ap === 'Pending' ? active : reviewDone ? done : wait
            },
            {
                key: 'dec',
                label: 'Decision',
                sub: decisionSub,
                dotClass: decisionDone ? done : wait
            }
        ];
    }

    handleClaimSelect(event) {
        this.selectedClaim = event.detail.claim;
    }
}