import { LightningElement, api, wire } from 'lwc';
import listClaimsForAccount from '@salesforce/apex/WC_AccountClaimsDashboardController.listClaimsForAccount';

const PAGE_SIZE = 8;

const STANDARD_COLUMNS = [
    {
        label: 'Claim',
        fieldName: 'recordUrl',
        type: 'url',
        typeAttributes: { label: { fieldName: 'name' }, target: '_self' }
    },
    { label: 'Status', fieldName: 'status', type: 'text' },
    { label: 'Approval', fieldName: 'approvalResult', type: 'text' },
    {
        label: 'Approval date',
        fieldName: 'approvedAtMs',
        type: 'date',
        typeAttributes: {
            year: 'numeric',
            month: 'short',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit'
        }
    },
    { label: 'Channel', fieldName: 'submissionChannel', type: 'text' },
    {
        label: 'Effective date',
        fieldName: 'effectiveDate',
        type: 'date-local'
    },
    {
        label: 'Created',
        fieldName: 'createdDateMs',
        type: 'date',
        typeAttributes: {
            year: 'numeric',
            month: 'short',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit'
        }
    },
    {
        label: 'Est. amount',
        fieldName: 'estimatedAmount',
        type: 'number',
        typeAttributes: { minimumFractionDigits: 2, maximumFractionDigits: 2 }
    },
    {
        label: 'Summary',
        fieldName: 'summary',
        type: 'text',
        wrapText: true,
        initialWidth: 260
    }
];

const PORTAL_COLUMNS = [
    {
        label: 'CLAIM ID',
        fieldName: 'recordUrl',
        type: 'url',
        typeAttributes: { label: { fieldName: 'name' }, target: '_self' }
    },
    { label: 'VIN', fieldName: 'vehicleVin', type: 'text', initialWidth: 130 },
    { label: 'VEHICLE', fieldName: 'vehicleDisplay', type: 'text', initialWidth: 160 },
    {
        label: 'ISSUE',
        fieldName: 'issueDisplay',
        type: 'text',
        wrapText: true,
        initialWidth: 200
    },
    { label: 'CHANNEL', fieldName: 'submissionChannel', type: 'text', initialWidth: 110 },
    { label: 'STATUS', fieldName: 'rowStatusDisplay', type: 'text', initialWidth: 140 },
    { label: 'PROCESSING', fieldName: 'processingHint', type: 'text', initialWidth: 130 }
];

export default class WcAccountClaimsTable extends LightningElement {
    @api accountId;
    @api recordId;

    /** Hub layout: toolbar, portal columns, pagination, row selection events. */
    @api embedded = false;

    searchKey = '';
    statusFilter = '';
    channelFilter = '';
    currentPage = 1;
    selectedRowIds = [];
    claims;
    _listWireAccountId;

    get resolvedAccountId() {
        const id = this.accountId || this.recordId;
        return id ? id : undefined;
    }

    @wire(listClaimsForAccount, { accountId: '$resolvedAccountId' })
    wiredClaims(result) {
        this.claims = result;
        if (result.data && this.resolvedAccountId) {
            const id = this.resolvedAccountId;
            if (this._listWireAccountId !== id) {
                this._listWireAccountId = id;
                this.resetFiltersForNewData();
            }
        }
    }

    get columns() {
        return this.embedded ? PORTAL_COLUMNS : STANDARD_COLUMNS;
    }

    get hasAccountContext() {
        return Boolean(this.resolvedAccountId);
    }

    get isLoading() {
        if (!this.hasAccountContext) {
            return false;
        }
        const w = this.claims;
        return w === undefined || (w.data === undefined && w.error === undefined);
    }

    get loadError() {
        const err = this.claims?.error;
        if (err) {
            return this.reduceError(err);
        }
        return undefined;
    }

    get rawRows() {
        const data = this.claims?.data;
        if (!data) {
            return [];
        }
        return data.map((row) => ({
            ...row,
            recordUrl: `/lightning/r/Claim/${row.id}/view`,
            createdDateMs: row.createdDate ? Date.parse(row.createdDate) : null,
            approvedAtMs: row.approvedAt ? Date.parse(row.approvedAt) : null,
            vehicleVin: row.vehicleVin || '—',
            vehicleDisplay: row.vehicleDisplay || '—',
            issueDisplay: row.issueDisplay || row.summary || '—',
            rowStatusDisplay: [row.status, row.approvalResult].filter(Boolean).join(' · ') || '—',
            submissionChannel: row.submissionChannel || '—',
            processingHint: row.processingHint || '—'
        }));
    }

    get statusOptions() {
        return [
            { label: 'All statuses', value: '' },
            { label: 'Pending', value: 'Pending' },
            { label: 'Approved', value: 'Approved' },
            { label: 'Rejected', value: 'Rejected' }
        ];
    }

    get channelOptions() {
        const opts = [{ label: 'All channels', value: '' }];
        const seen = new Set();
        for (const r of this.rawRows) {
            const ch = r.submissionChannel;
            if (ch && ch !== '—' && !seen.has(ch)) {
                seen.add(ch);
                opts.push({ label: ch, value: ch });
            }
        }
        return opts;
    }

    get filteredRows() {
        const q = (this.searchKey || '').trim().toLowerCase();
        const sf = this.statusFilter;
        const cf = this.channelFilter;
        return this.rawRows.filter((r) => {
            if (sf && (r.approvalResult || '') !== sf) {
                return false;
            }
            if (cf && (r.submissionChannel || '') !== cf) {
                return false;
            }
            if (!q) {
                return true;
            }
            const hay = [
                r.name,
                r.vehicleVin,
                r.vehicleDisplay,
                r.issueDisplay,
                r.submissionChannel,
                r.status,
                r.approvalResult
            ]
                .join(' ')
                .toLowerCase();
            return hay.includes(q);
        });
    }

    get totalFiltered() {
        return this.filteredRows.length;
    }

    get totalPages() {
        return Math.max(1, Math.ceil(this.totalFiltered / PAGE_SIZE));
    }

    get pagedRows() {
        const start = (this.currentPage - 1) * PAGE_SIZE;
        return this.filteredRows.slice(start, start + PAGE_SIZE);
    }

    get tableData() {
        return this.embedded ? this.pagedRows : this.rawRows;
    }

    get showingFrom() {
        if (!this.totalFiltered) {
            return 0;
        }
        return (this.currentPage - 1) * PAGE_SIZE + 1;
    }

    get showingTo() {
        if (!this.totalFiltered) {
            return 0;
        }
        return Math.min(this.currentPage * PAGE_SIZE, this.totalFiltered);
    }

    get pageSummary() {
        return `Page ${this.currentPage} of ${this.totalPages}`;
    }

    get disablePrev() {
        return this.currentPage <= 1;
    }

    get disableNext() {
        return this.currentPage >= this.totalPages;
    }

    get listHeaderCount() {
        return `${this.totalFiltered} record${this.totalFiltered === 1 ? '' : 's'}`;
    }

    get datatableHideCheckbox() {
        return !this.embedded;
    }

    get datatableMaxRowSelection() {
        return this.embedded ? 1 : 0;
    }

    get datatableShowRowNumber() {
        return !this.embedded;
    }

    get selectedRowsForGrid() {
        const onPage = new Set(this.tableData.map((r) => r.id));
        return this.selectedRowIds.filter((id) => onPage.has(id));
    }

    resetFiltersForNewData() {
        this.searchKey = '';
        this.statusFilter = '';
        this.channelFilter = '';
        this.currentPage = 1;
        this.selectedRowIds = [];
        if (this.embedded) {
            this.dispatchEvent(
                new CustomEvent('claimselect', {
                    bubbles: true,
                    composed: true,
                    detail: { claim: null }
                })
            );
        }
    }

    handleSearch(event) {
        this.searchKey = event.target.value;
        this.currentPage = 1;
    }

    handleStatusFilter(event) {
        this.statusFilter = event.detail.value;
        this.currentPage = 1;
    }

    handleChannelFilter(event) {
        this.channelFilter = event.detail.value;
        this.currentPage = 1;
    }

    handlePrev() {
        if (this.currentPage > 1) {
            this.currentPage -= 1;
        }
    }

    handleNext() {
        if (this.currentPage < this.totalPages) {
            this.currentPage += 1;
        }
    }

    handleRowSelection(event) {
        const selected = event.detail.selectedRows || [];
        this.selectedRowIds = selected.map((r) => r.id);
        const claim = selected.length ? selected[0] : null;
        this.dispatchEvent(
            new CustomEvent('claimselect', {
                bubbles: true,
                composed: true,
                detail: { claim }
            })
        );
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