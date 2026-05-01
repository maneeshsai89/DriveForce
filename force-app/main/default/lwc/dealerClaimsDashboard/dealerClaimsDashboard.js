import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import USER_ID from '@salesforce/user/Id';
import USER_CONTACT_ID_FIELD from '@salesforce/schema/User.ContactId';
import CONTACT_ACCOUNT_ID_FIELD from '@salesforce/schema/Contact.AccountId';
import NAME_FIELD from '@salesforce/schema/Account.Name';
import getClaimMetricsByAccount from '@salesforce/apex/WC_AccountClaimsDashboardController.getClaimMetricsByAccount';
import listClaimsForAccount from '@salesforce/apex/WC_AccountClaimsDashboardController.listClaimsForAccount';
import getFrequentVinsLast30Days from '@salesforce/apex/WC_AccountClaimsDashboardController.getFrequentVinsLast30Days';
import STOCK_CAR_01 from '@salesforce/resourceUrl/dealerStockCar01';
import STOCK_CAR_02 from '@salesforce/resourceUrl/dealerStockCar02';
import STOCK_CAR_03 from '@salesforce/resourceUrl/dealerStockCar03';
import STOCK_CAR_04 from '@salesforce/resourceUrl/dealerStockCar04';
import STOCK_CAR_05 from '@salesforce/resourceUrl/dealerStockCar05';
import STOCK_CAR_06 from '@salesforce/resourceUrl/dealerStockCar06';
import STOCK_CAR_07 from '@salesforce/resourceUrl/dealerStockCar07';
import STOCK_CAR_08 from '@salesforce/resourceUrl/dealerStockCar08';

/** Stock photos (Static Resources). Same VIN always maps to the same image via hash % length. */
const VEHICLE_IMAGE_POOL = [
    STOCK_CAR_01,
    STOCK_CAR_02,
    STOCK_CAR_03,
    STOCK_CAR_04,
    STOCK_CAR_05,
    STOCK_CAR_06,
    STOCK_CAR_07,
    STOCK_CAR_08
];

const USER_FIELDS = [USER_CONTACT_ID_FIELD];
const CONTACT_FIELDS = [CONTACT_ACCOUNT_ID_FIELD];
const ACCOUNT_FIELDS = [NAME_FIELD];
const MS_IN_DAY = 24 * 60 * 60 * 1000;
const FREQUENT_VIN_WINDOW_DAYS = 30;

/** Partner tiers: volume + approval rate once enough decided claims (per program table). */
const DEALER_TIERS = [
    { key: 'standard', label: 'Standard', minClaims: 0, minDecided: 0, minRate: 0 },
    { key: 'premier', label: 'Premier', minClaims: 12, minDecided: 3, minRate: 75 },
    { key: 'elite', label: 'Elite', minClaims: 35, minDecided: 5, minRate: 88 }
];

const TIER_BENEFITS = {
    premier: [
        'Fast-track escalation line for complex claims',
        'Premier dealer badge + spotlight in quarterly newsletter',
        'Enhanced co-op eligibility on approved claim volume'
    ],
    elite: [
        'Fast-track escalation line for complex claims',
        'Elite dealer badge + spotlight in quarterly newsletter',
        'Enhanced co-op eligibility on approved claim volume'
    ],
    eliteMax: [
        'Top-tier escalation path and dealer success manager',
        'Elite badge + featured dealer recognition',
        'Maximum program benefits on referrals and claim incentives'
    ]
};

const TABLE_COLUMNS = [
    { label: 'Claim #', fieldName: 'claimNumber', type: 'text' },
    { label: 'VIN', fieldName: 'vin', type: 'text' },
    { label: 'Issue', fieldName: 'issue', type: 'text', wrapText: true },
    { label: 'Status', fieldName: 'status', type: 'text' },
    { label: 'Est. Value', fieldName: 'formattedValue', type: 'text' }
];

export default class DealerClaimsDashboard extends LightningElement {
    @api dealershipName = 'Summit Motors';
    @api dealershipLocation = 'Portland, OR';
    @api primaryColor = '#0B5394';
    @api accentColor = '#FF6B35';
    @api accountId;

    searchTerm = '';
    activeStatusFilter = 'all';
    selectedClaimId = null;
    viewMode = 'card';

    @track isNarrowViewport = false;

    _syncStart = Date.now();
    _themeApplied = false;
    _claimsWire;
    _metricsWire;
    _frequentVinWire;

    _viewportMql;
    _onViewportChangeBound;

    connectedCallback() {
        this._viewportMql = window.matchMedia('(max-width: 768px)');
        this._onViewportChangeBound = this.syncNarrowViewport.bind(this);
        if (this._viewportMql.addEventListener) {
            this._viewportMql.addEventListener('change', this._onViewportChangeBound);
        } else if (this._viewportMql.addListener) {
            this._viewportMql.addListener(this._onViewportChangeBound);
        }
        this.syncNarrowViewport();
        window.addEventListener('keydown', this.handleGlobalKeydown);
    }

    disconnectedCallback() {
        if (this._viewportMql && this._onViewportChangeBound) {
            if (this._viewportMql.removeEventListener) {
                this._viewportMql.removeEventListener('change', this._onViewportChangeBound);
            } else if (this._viewportMql.removeListener) {
                this._viewportMql.removeListener(this._onViewportChangeBound);
            }
        }
        window.removeEventListener('keydown', this.handleGlobalKeydown);
    }

    syncNarrowViewport() {
        const narrow = this._viewportMql ? this._viewportMql.matches : false;
        this.isNarrowViewport = narrow;
        if (narrow && this.viewMode === 'table') {
            this.viewMode = 'card';
        }
    }

    handleGlobalKeydown = (event) => {
        if (event.key !== 'Escape' || !this.selectedClaimId || !this.isNarrowViewport) {
            return;
        }
        this.handleCloseDetail();
    };

    @wire(getRecord, { recordId: USER_ID, fields: USER_FIELDS })
    wiredUser;

    @wire(getRecord, { recordId: '$loggedInContactId', fields: CONTACT_FIELDS })
    wiredContact;

    @wire(getRecord, { recordId: '$resolvedAccountId', fields: ACCOUNT_FIELDS })
    wiredAccount;

    @wire(getClaimMetricsByAccount, { accountId: '$resolvedAccountId' })
    wiredMetrics(result) {
        this._metricsWire = result;
    }

    @wire(listClaimsForAccount, { accountId: '$resolvedAccountId' })
    wiredClaims(result) {
        this._claimsWire = result;
        if (this.selectedClaimId && !this.normalizedClaims.some((c) => c.id === this.selectedClaimId)) {
            this.selectedClaimId = null;
        }
    }

    @wire(getFrequentVinsLast30Days, { accountId: '$resolvedAccountId' })
    wiredFrequentVins(result) {
        this._frequentVinWire = result;
    }

    renderedCallback() {
        if (this._themeApplied) {
            return;
        }
        this._themeApplied = true;
        this.template.host.style.setProperty('--brand-primary', this.primaryColor || '#0B5394');
        this.template.host.style.setProperty('--brand-accent', this.accentColor || '#FF6B35');
    }

    get loggedInContactId() {
        return getFieldValue(this.wiredUser?.data, USER_CONTACT_ID_FIELD);
    }

    get loggedInAccountId() {
        return getFieldValue(this.wiredContact?.data, CONTACT_ACCOUNT_ID_FIELD);
    }

    get resolvedAccountId() {
        return this.accountId || this.loggedInAccountId || undefined;
    }

    get hasContext() {
        return Boolean(this.resolvedAccountId);
    }

    get accountName() {
        return getFieldValue(this.wiredAccount?.data, NAME_FIELD);
    }

    get heroDealershipName() {
        return this.accountName || this.dealershipName;
    }

    get syncLabel() {
        return `Live · Last synced ${this.formatRelative(this._syncStart)}`;
    }

    get greetingPeriod() {
        const hour = new Date().getHours();
        if (hour < 12) {
            return 'morning';
        }
        if (hour < 17) {
            return 'afternoon';
        }
        return 'evening';
    }

    get greetingEyebrow() {
        const d = new Date();
        const day = d.toLocaleDateString('en-US', { weekday: 'long' }).toUpperCase();
        const date = d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }).toUpperCase();
        return `${day} · ${date} · ${this.syncLabel.toUpperCase()}`;
    }

    get greetingSummary() {
        return `Recovered ${this.formattedValueRecovered} in approved claims so far. ${this.underReviewCount} claim${this.underReviewCount === 1 ? '' : 's'} are awaiting decisions.`;
    }

    get claimsWireLoading() {
        return this.hasContext && !this._claimsWire?.data && !this._claimsWire?.error;
    }

    get metricsWireLoading() {
        return this.hasContext && !this._metricsWire?.data && !this._metricsWire?.error;
    }

    get frequentVinWireLoading() {
        if (!this.hasContext) {
            return false;
        }
        const w = this._frequentVinWire;
        if (w === undefined) {
            return true;
        }
        return w.data === undefined && w.error === undefined;
    }

    get isLoading() {
        return this.claimsWireLoading || this.metricsWireLoading || this.frequentVinWireLoading;
    }

    get loadError() {
        const base = this.reduceError(this._claimsWire?.error) || this.reduceError(this._metricsWire?.error);
        if (base) {
            return base;
        }
        if (this._frequentVinWire?.error && !this._claimsWire?.data) {
            return this.reduceError(this._frequentVinWire.error);
        }
        return undefined;
    }

    get normalizedClaims() {
        const rows = this._claimsWire?.data || [];
        return rows.map((row, index) => this.normalizeClaim(row, index));
    }

    get totalClaims() {
        return this._metricsWire?.data?.totalRaised ?? this.normalizedClaims.length;
    }

    get underReviewCount() {
        return this._metricsWire?.data?.pendingCount ?? this.normalizedClaims.filter((c) => c.statusKey === 'underreview').length;
    }

    get approvedCount() {
        return this._metricsWire?.data?.approvedCount ?? this.normalizedClaims.filter((c) => c.statusKey === 'approved').length;
    }

    get rejectedCount() {
        return this._metricsWire?.data?.rejectedCount ?? this.normalizedClaims.filter((c) => c.statusKey === 'rejected').length;
    }

    get submittedCount() {
        return this.normalizedClaims.filter((c) => c.statusKey === 'submitted').length;
    }

    get approvalRate() {
        const decided = this.approvedCount + this.rejectedCount;
        if (decided === 0) {
            return 0;
        }
        return Math.round((this.approvedCount / decided) * 100);
    }

    get totalValueRecovered() {
        return this.normalizedClaims
            .filter((c) => c.statusKey === 'approved')
            .reduce((sum, c) => sum + c.estimatedValue, 0);
    }

    get formattedValueRecovered() {
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD',
            maximumFractionDigits: 0
        }).format(this.totalValueRecovered);
    }

    get totalClaimsTrend() {
        const monthCount = this._metricsWire?.data?.claimsThisMonth ?? 0;
        return monthCount > 0 ? `↑ ${monthCount} this month` : 'No new claims this month';
    }

    get underReviewTrend() {
        return this.underReviewCount ? 'Awaiting decision' : 'No pending reviews';
    }

    get decidedClaimsCount() {
        return this.approvedCount + this.rejectedCount;
    }

    get claimRateDisplay() {
        if (this.decidedClaimsCount === 0) {
            return '—';
        }
        return `${this.approvalRate}%`;
    }

    tierQualifies(tierIndex) {
        const t = DEALER_TIERS[tierIndex];
        if (!t || this.totalClaims < t.minClaims) {
            return false;
        }
        if (this.decidedClaimsCount < t.minDecided) {
            return true;
        }
        return this.approvalRate >= t.minRate;
    }

    get currentTierIndex() {
        for (let i = DEALER_TIERS.length - 1; i >= 0; i--) {
            if (this.tierQualifies(i)) {
                return i;
            }
        }
        return 0;
    }

    get currentTierDef() {
        return DEALER_TIERS[this.currentTierIndex];
    }

    get tierBannerBadgeClass() {
        const key = this.currentTierDef?.key || 'standard';
        return `tier-banner-badge tier-banner-badge--${key}`;
    }

    get nextTierDef() {
        const n = this.currentTierIndex + 1;
        return n < DEALER_TIERS.length ? DEALER_TIERS[n] : null;
    }

    get isMaxTier() {
        return this.nextTierDef === null;
    }

    /** Combined progress (claims volume + rate) toward the next tier. */
    get tierProgressPercent() {
        if (this.isMaxTier) {
            return 100;
        }
        const cur = this.currentTierIndex;
        const next = cur + 1;
        const t0 = DEALER_TIERS[cur];
        const t1 = DEALER_TIERS[next];
        const claimsSpan = Math.max(1, t1.minClaims - t0.minClaims);
        const claimsProgress = Math.min(1, (this.totalClaims - t0.minClaims) / claimsSpan);
        let rateProgress = 1;
        if (this.decidedClaimsCount >= t1.minDecided) {
            rateProgress = Math.min(1, this.approvalRate / Math.max(1, t1.minRate));
        }
        return Math.round(Math.min(100, Math.max(0, (claimsProgress * 0.55 + rateProgress * 0.45) * 100)));
    }

    get tierCurrentDetailRows() {
        return [
            { id: 'tier', label: 'Tier', value: this.currentTierDef.label },
            { id: 'claims', label: 'Total claims', value: String(this.totalClaims) },
            { id: 'rate', label: 'Claim approval rate', value: this.claimRateDisplay }
        ];
    }

    get tierNextActionRows() {
        if (this.isMaxTier) {
            return [
                {
                    id: 'max',
                    text: 'You have reached the highest dealer tier. Keep submitting quality claims to maintain your standing.'
                }
            ];
        }
        const n = this.nextTierDef;
        const rows = [];
        const needClaims = Math.max(0, n.minClaims - this.totalClaims);
        if (needClaims > 0) {
            rows.push({
                id: 'vol',
                text: `Reach ${n.minClaims}+ total claims (${needClaims} more) — volume unlocks the next tier.`
            });
        }
        if (this.decidedClaimsCount < n.minDecided) {
            rows.push({
                id: 'dec',
                text: `Obtain at least ${n.minDecided} decided claims (approved or rejected) so we can measure approval rate against the ${n.minRate}% target.`
            });
        } else if (this.approvalRate < n.minRate) {
            rows.push({
                id: 'rate',
                text: `Improve claim approval rate from ${this.approvalRate}% to at least ${n.minRate}% among decided claims.`
            });
        }
        if (rows.length === 0) {
            rows.push({
                id: 'sync',
                text: 'You meet the published thresholds — tier elevation follows your account metrics on the next sync.'
            });
        }
        return rows;
    }

    get tierNextBenefitRows() {
        if (this.isMaxTier) {
            return TIER_BENEFITS.eliteMax.map((text, i) => ({ id: `b${i}`, text }));
        }
        const list = this.nextTierDef.key === 'premier' ? TIER_BENEFITS.premier : TIER_BENEFITS.elite;
        return list.map((text, i) => ({ id: `nb${i}`, text }));
    }

    get tierAdvanceHeadline() {
        if (this.isMaxTier) {
            return 'Elite dealer — benefits you have earned';
        }
        return `Advance to ${this.nextTierDef.label}`;
    }

    get tierBenefitsHeading() {
        if (this.isMaxTier) {
            return 'Your Elite benefits';
        }
        return `Benefits of ${this.nextTierDef.label} tier`;
    }

    get nextTierLabel() {
        if (this.isMaxTier) {
            return 'Elite (maintain)';
        }
        return this.nextTierDef.label;
    }

    /** Host sets --tier-meter-pct (0–100); fill width uses calc() so the bar matches tierProgressPercent. */
    get tierMeterStyle() {
        const p = Math.min(100, Math.max(0, this.tierProgressPercent));
        return `--tier-meter-pct: ${p};`;
    }

    get showTierProgress() {
        return this.hasContext && !this.isLoading && !this.loadError;
    }

    computeFrequentVinsFromClaims() {
        const cutoff = Date.now() - FREQUENT_VIN_WINDOW_DAYS * MS_IN_DAY;
        const byVin = new Map();
        for (const c of this.normalizedClaims) {
            if (!c.vin || c.vin === 'VIN unavailable') {
                continue;
            }
            const d = Date.parse(c.submittedDate);
            if (Number.isNaN(d) || d < cutoff) {
                continue;
            }
            if (!byVin.has(c.vin)) {
                byVin.set(c.vin, {
                    claimCount: 0,
                    vehicleDisplay: c.vehicle || '',
                    issueNormToCount: new Map(),
                    issueNormToLabel: new Map()
                });
            }
            const slot = byVin.get(c.vin);
            slot.claimCount += 1;
            if (!slot.vehicleDisplay && c.vehicle) {
                slot.vehicleDisplay = c.vehicle;
            }
            const raw = (c.issue || '').trim();
            const norm = raw ? raw.toLowerCase() : '::none::';
            const label = raw || 'No description';
            slot.issueNormToCount.set(norm, (slot.issueNormToCount.get(norm) || 0) + 1);
            if (!slot.issueNormToLabel.has(norm)) {
                slot.issueNormToLabel.set(norm, label);
            }
        }
        return [...byVin.entries()]
            .map(([vin, data]) => {
                const issueBreakdown = [...data.issueNormToCount.entries()]
                    .map(([norm, cnt]) => ({
                        issueLabel: data.issueNormToLabel.get(norm),
                        claimCount: cnt
                    }))
                    .sort(
                        (a, b) =>
                            b.claimCount - a.claimCount ||
                            (a.issueLabel || '').localeCompare(b.issueLabel || '')
                    );
                return {
                    vin,
                    claimCount: data.claimCount,
                    vehicleDisplay: data.vehicleDisplay,
                    issueBreakdown
                };
            })
            .sort((a, b) => b.claimCount - a.claimCount || a.vin.localeCompare(b.vin));
    }

    truncateVinInsightText(text, maxLen = 220) {
        if (!text || typeof text !== 'string') {
            return '';
        }
        const t = text.trim();
        if (t.length <= maxLen) {
            return t;
        }
        return `${t.slice(0, maxLen - 1)}…`;
    }

    get frequentVinRowsSorted() {
        const fr = this._frequentVinWire;
        if (fr !== undefined && fr.data !== undefined && !fr.error) {
            return (fr.data || []).map((r) => ({
                vin: r.vin,
                claimCount: r.claimCount,
                vehicleDisplay: r.vehicleDisplay || '',
                issueBreakdown: Array.isArray(r.issueBreakdown) ? r.issueBreakdown : []
            }));
        }
        if (fr?.error && this._claimsWire?.data) {
            return this.computeFrequentVinsFromClaims();
        }
        return [];
    }

    get frequentVinWindowDays() {
        return FREQUENT_VIN_WINDOW_DAYS;
    }

    get topFrequentVinsDisplay() {
        return this.frequentVinRowsSorted.slice(0, 5).map((r) => {
            const breakdown = Array.isArray(r.issueBreakdown) ? r.issueBreakdown : [];
            const issueBreakdownDisplay = breakdown.map((it, idx) => {
                const n = it.claimCount;
                return {
                    key: `${r.vin}-issue-${idx}`,
                    issueLabel: this.truncateVinInsightText(it.issueLabel || '', 72),
                    claimCount: n,
                    claimCountPlural: n === 1 ? '' : 's',
                    issueCountTitle: `${n} claim${n === 1 ? '' : 's'}`
                };
            });
            const vehicle = (r.vehicleDisplay || '').trim();
            return {
                vin: r.vin,
                claimCount: r.claimCount,
                key: r.vin,
                vinInsightTitle: vehicle ? `${r.vin} · ${vehicle}` : r.vin,
                claimCountPlural: r.claimCount === 1 ? '' : 's',
                claimSummaryTitle: `${r.claimCount} claim${r.claimCount === 1 ? '' : 's'}`,
                issueBreakdownDisplay,
                hasIssueBreakdown: issueBreakdownDisplay.length > 0
            };
        });
    }

    get hasTopFrequentVinsRows() {
        return this.topFrequentVinsDisplay.length > 0;
    }

    get frequentVinExpectation() {
        const rows = this.frequentVinRowsSorted;
        if (rows.length === 0) {
            return 'No claims with a linked VIN were opened in the last 30 days. When volume shows up here, use it to calibrate review depth, documentation, and customer expectations.';
        }
        const top = rows[0];
        const max = top.claimCount;
        const multiVinCount = rows.filter((r) => r.claimCount >= 2).length;
        if (max >= 4) {
            return `${top.vin} has ${max} claims in this window — expect intensified review, possible holds for prior service history, and brief your team before the next filing on this unit.`;
        }
        if (max === 3) {
            return `${top.vin} has three claims — manufacturers often request expanded documentation on the third touch; gather VIN history and noted repairs before submitting again.`;
        }
        if (multiVinCount >= 2) {
            return `${multiVinCount} VINs each have multiple claims — pattern risk is elevated; tighten photo packs and diagnostic notes on new submissions so decisions stay on track.`;
        }
        if (max === 2) {
            return `${top.vin} was claimed twice — second claims on the same unit typically see longer review; set customer expectations and align estimates early.`;
        }
        return 'No VIN has more than one claim in the last 30 days — processing should follow your usual approval cadence; keep monitoring if volume spikes on a single unit.';
    }

    get filteredClaims() {
        let result = this.normalizedClaims;

        if (this.activeStatusFilter !== 'all') {
            result = result.filter((c) => c.statusKey === this.activeStatusFilter);
        }

        if (this.searchTerm) {
            const term = this.searchTerm.toLowerCase();
            result = result.filter((c) =>
                c.vin.toLowerCase().includes(term) ||
                c.claimNumber.toLowerCase().includes(term) ||
                c.vehicle.toLowerCase().includes(term) ||
                c.issue.toLowerCase().includes(term) ||
                c.customer.toLowerCase().includes(term)
            );
        }

        return result.map((c) => ({
            ...c,
            isSelected: c.id === this.selectedClaimId,
            cardClass: `claim-card ${c.id === this.selectedClaimId ? 'is-selected' : ''}`,
            statusBadgeClass: `status-badge status-${c.statusColor}`,
            priorityClass: `priority-pill priority-${c.priority.toLowerCase()}`,
            formattedValue:
                c.estimatedValue > 0
                ? new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', maximumFractionDigits: 0 }).format(c.estimatedValue)
                : '—'
        }));
    }

    get hasFilteredClaims() {
        return this.filteredClaims.length > 0;
    }

    get showMobileClaimsHint() {
        return this.isNarrowViewport && !this.selectedClaimId && this.hasFilteredClaims;
    }

    get showViewModeToggle() {
        return !this.isNarrowViewport;
    }

    get emptyListMessage() {
        if (this.searchTerm) {
            return 'No claims matched your search. Try another VIN, claim number, or vehicle.';
        }
        if (this.activeStatusFilter !== 'all') {
            return 'No claims found for the selected status.';
        }
        return 'No claims available for this dealer account yet.';
    }

    get selectedClaim() {
        if (!this.selectedClaimId) {
            return null;
        }
        const claim = this.normalizedClaims.find((c) => c.id === this.selectedClaimId);
        if (!claim) {
            return null;
        }
        return {
            ...claim,
            formattedValue:
                claim.estimatedValue > 0
                ? new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', maximumFractionDigits: 0 }).format(claim.estimatedValue)
                : 'Pending',
            statusBadgeClass: `detail-status-badge status-${claim.statusColor}`,
            timeline: this.buildTimeline(claim),
            insights: this.buildClaimInsights(claim)
        };
    }

    get hasSelectedClaim() {
        return this.selectedClaim !== null;
    }

    get cardViewClass() {
        return `view-toggle-btn ${this.viewMode === 'card' ? 'is-active' : ''}`;
    }

    get tableViewClass() {
        return `view-toggle-btn ${this.viewMode === 'table' ? 'is-active' : ''}`;
    }

    get isCardView() {
        return this.isNarrowViewport || this.viewMode === 'card';
    }

    get tableColumns() {
        return TABLE_COLUMNS;
    }

    get tableRows() {
        return this.filteredClaims.map((c) => ({
            id: c.id,
            claimNumber: c.claimNumber,
            vin: c.vin,
            vehicle: c.vehicle,
            issue: c.issue,
            status: c.status,
            WC_Approval_Channel__c: c.WC_Approval_Channel__c,
            approvedAt: c.approvedAt,
            daysOpen: c.daysOpen,
            formattedValue: c.formattedValue
        }));
    }

    get selectedRowsForTable() {
        return this.selectedClaimId ? [this.selectedClaimId] : [];
    }

    get statusFilterOptions() {
        return [
            { label: 'All', value: 'all', isActive: this.activeStatusFilter === 'all' },
            { label: 'Submitted', value: 'submitted', isActive: this.activeStatusFilter === 'submitted' },
            { label: 'Under Review', value: 'underreview', isActive: this.activeStatusFilter === 'underreview' },
            { label: 'Approved', value: 'approved', isActive: this.activeStatusFilter === 'approved' },
            { label: 'Rejected', value: 'rejected', isActive: this.activeStatusFilter === 'rejected' }
        ].map(o => ({
            ...o,
            class: `chip ${o.isActive ? 'is-active' : ''}`
        }));
    }

    /** Maps claim text/category to a manufacturer-review component (defaults to HV battery for EV warranty demos). */
    inferInsightComponentFocus(claim) {
        const issue = (claim.issue || '').toLowerCase();
        const cat = (claim.issueCategory || '').toLowerCase();
        if (/\b(battery|hv\b|high voltage|lithium|kwh|range loss|12v system)\b/.test(issue) || cat.includes('battery')) {
            return 'High Voltage Battery';
        }
        if (cat.includes('charging') || issue.includes('charge')) {
            return 'High Voltage Charging System';
        }
        if (cat.includes('electronics') || issue.includes('sensor') || issue.includes('electr')) {
            return 'High Voltage Battery Management System';
        }
        if (cat.includes('braking') || issue.includes('brake')) {
            return 'Brake / Regenerative Integration';
        }
        if (issue.includes('engine') || issue.includes('sound') || issue.includes('noise') || issue.includes('motor')) {
            return 'High Voltage Battery (hybrid / e-assist stack)';
        }
        return 'High Voltage Battery';
    }

    /** Peer claims on this account with same issue category filed in the last 90 days (excludes current). */
    countSimilarIssueCategoryLast90Days(claim) {
        if (!claim?.issueCategory || !claim?.submittedDate) {
            return 0;
        }
        const cutoff = Date.now() - 90 * MS_IN_DAY;
        return this.normalizedClaims.filter((c) => {
            if (c.id === claim.id) {
                return false;
            }
            if (c.issueCategory !== claim.issueCategory) {
                return false;
            }
            const d = Date.parse(c.submittedDate);
            if (Number.isNaN(d)) {
                return false;
            }
            return d >= cutoff;
        }).length;
    }

    buildClaimInsights(claim) {
        const similar = this.countSimilarIssueCategoryLast90Days(claim);
        const componentFocus = this.inferInsightComponentFocus(claim);
        const similarPhrase = similar === 1 ? 'once' : `${similar} times`;
        return {
            hasPeerReports: similar > 0,
            similarCount: similar,
            similarPhrase,
            componentFocus
        };
    }

    buildTimeline(claim) {
        const decisionDateFromClaim = () => {
            const fromField = this.toIsoDate(claim.approvedAt);
            if (fromField !== '—') {
                return fromField;
            }
            return this.addDays(claim.submittedDate, claim.daysOpen);
        };
        const base = [
            { label: 'Submitted', date: claim.submittedDate, complete: true, icon: '📥' },
            { label: 'Under Review', date: claim.submittedDate, complete: claim.statusKey !== 'submitted', icon: '🔍' }
        ];
        if (claim.statusKey === 'approved') {
            base.push({ label: 'Approved', date: decisionDateFromClaim(), complete: true, icon: '✅' });
        } else if (claim.statusKey === 'rejected') {
            base.push({ label: 'Rejected', date: decisionDateFromClaim(), complete: true, icon: '❌' });
        } else if (claim.statusKey === 'underreview') {
            base.push({ label: 'Decision Pending', date: '—', complete: false, icon: '⏳' });
        }
        return base.map((step, idx) => ({
            ...step,
            id: `step-${idx}`,
            class: `timeline-step ${step.complete ? 'is-complete' : 'is-pending'}`
        }));
    }

    addDays(dateStr, days) {
        const d = new Date(dateStr);
        d.setDate(d.getDate() + days);
        return d.toISOString().split('T')[0];
    }

    formatMileageDisplay(assetUsageValue) {
        if (assetUsageValue == null || assetUsageValue === '') {
            return '—';
        }
        const n = Number(assetUsageValue);
        if (Number.isNaN(n)) {
            return '—';
        }
        return new Intl.NumberFormat('en-US', { maximumFractionDigits: 0 }).format(Math.round(n));
    }

    normalizeClaim(row, index) {
        const statusParts = this.normalizeStatus(row.approvalResult, row.status);
        const issue = row.issueDisplay || 'Issue details not provided';
        const created = row.createdDate || null;
        const estimatedValue = Number(row.estimatedAmount) || 0;
        const daysOpen = this.computeDaysOpen(created);
        const priority = this.derivePriority(statusParts.statusKey, estimatedValue, daysOpen);
        const vehicle = row.vehicleDisplay || '';
        return {
            id: row.id,
            claimNumber: row.name || row.id || `CLAIM-${index + 1}`,
            vin: row.vehicleVin || 'VIN unavailable',
            vehicle,
            vehicleImage: this.pickVehicleImage(row.vehicleVin, row.id),
            issue,
            issueCategory: this.deriveIssueCategory(issue),
            WC_Approval_Channel__c: row.approvalChannel || '—',
            status: statusParts.statusLabel,
            statusKey: statusParts.statusKey,
            statusColor: statusParts.statusColor,
            submittedDate: this.toIsoDate(created),
            approvedAt: row.approvedAt ?? null,
            customer: this.heroDealershipName,
            mileage: this.formatMileageDisplay(row.assetUsageValue),
            priority,
            estimatedValue,
            daysOpen
        };
    }

    normalizeStatus(approvalResult, status) {
        const raw = (approvalResult || status || '').toLowerCase();
        if (raw === 'approved') {
            return { statusLabel: 'Approved', statusKey: 'approved', statusColor: 'approved' };
        }
        if (raw === 'rejected') {
            return { statusLabel: 'Rejected', statusKey: 'rejected', statusColor: 'rejected' };
        }
        if (raw === 'pending') {
            return { statusLabel: 'Under Review', statusKey: 'underreview', statusColor: 'review' };
        }
        return { statusLabel: 'Submitted', statusKey: 'submitted', statusColor: 'submitted' };
    }

    computeDaysOpen(createdDateString) {
        if (!createdDateString) {
            return 0;
        }
        const createdMs = Date.parse(createdDateString);
        if (Number.isNaN(createdMs)) {
            return 0;
        }
        const diff = Date.now() - createdMs;
        return Math.max(0, Math.floor(diff / MS_IN_DAY));
    }

    derivePriority(statusKey, estimatedValue, daysOpen) {
        if (statusKey === 'underreview' && (estimatedValue >= 5000 || daysOpen >= 7)) {
            return 'High';
        }
        if (estimatedValue >= 2000 || daysOpen >= 3) {
            return 'Medium';
        }
        return 'Low';
    }

    deriveIssueCategory(issue) {
        const txt = issue.toLowerCase();
        if (txt.includes('battery') || txt.includes('range')) {
            return 'Battery / Range';
        }
        if (txt.includes('charge')) {
            return 'Charging';
        }
        if (txt.includes('brake')) {
            return 'Braking';
        }
        if (txt.includes('screen') || txt.includes('electr') || txt.includes('sensor')) {
            return 'Electronics';
        }
        return 'General';
    }

    /**
     * One stable image per VIN: same string always picks the same pool slot.
     * Missing VIN falls back to claim id so the row still has a fixed image.
     */
    pickVehicleImage(vehicleVin, claimIdFallback) {
        const raw = (vehicleVin || '').trim();
        const key =
            raw && raw.toLowerCase() !== 'vin unavailable'
                ? raw.toUpperCase()
                : String(claimIdFallback || '');
        if (!key) {
            return VEHICLE_IMAGE_POOL[0];
        }
        let h = 0;
        for (let i = 0; i < key.length; i++) {
            h = (Math.imul(31, h) + key.charCodeAt(i)) | 0;
        }
        const idx = (h >>> 0) % VEHICLE_IMAGE_POOL.length;
        return VEHICLE_IMAGE_POOL[idx];
    }

    toIsoDate(dateLike) {
        if (!dateLike) {
            return '—';
        }
        const d = new Date(dateLike);
        if (Number.isNaN(d.getTime())) {
            return '—';
        }
        return d.toISOString().split('T')[0];
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

    handleSearch(event) {
        this.searchTerm = event.target.value;
    }

    handleStatusFilter(event) {
        this.activeStatusFilter = event.currentTarget.dataset.value;
    }

    handleClaimSelect(event) {
        const claimId = event.currentTarget.dataset.id;
        const nextId = this.selectedClaimId === claimId ? null : claimId;
        this.selectedClaimId = nextId;
        if (nextId) {
            Promise.resolve().then(() => this.scrollDetailPanelToTop());
        }
    }

    handleViewModeToggle(event) {
        if (this.isNarrowViewport) {
            return;
        }
        this.viewMode = event.currentTarget.dataset.mode;
    }

    handleTableRowSelection(event) {
        const selected = event.detail.selectedRows || [];
        const nextId = selected.length ? selected[0].id : null;
        this.selectedClaimId = nextId;
        if (nextId) {
            Promise.resolve().then(() => this.scrollDetailPanelToTop());
        }
    }

    scrollDetailPanelToTop() {
        const panel = this.template.querySelector('.detail-panel');
        if (panel) {
            panel.scrollTop = 0;
        }
    }

    handleExportReport() {
        const rows = this.filteredClaims;
        if (!rows.length) {
            return;
        }

        const headers = [
            'Claim Number',
            'VIN',
            'Vehicle',
            'Issue',
            'Issue Category',
            'Status',
            'Channel',
            'Approval Date',
            'Priority',
            'Days Open',
            'Estimated Value',
            'Submitted Date',
            'Customer'
        ];

        const csvLines = [headers.join(',')];
        rows.forEach((row) => {
            const values = [
                row.claimNumber,
                row.vin,
                row.vehicle,
                row.issue,
                row.issueCategory,
                row.status,
                row.WC_Approval_Channel__c,
                this.toIsoDate(row.approvedAt),
                row.priority,
                row.daysOpen,
                row.estimatedValue,
                row.submittedDate,
                row.customer
            ];
            csvLines.push(values.map((value) => this.escapeCsvValue(value)).join(','));
        });

        const csv = csvLines.join('\r\n');
        // LWR + LWS can block Blob/ObjectURL MIME flows. Use a data URI instead.
        const csvWithBom = `\uFEFF${csv}`;
        const url = `data:text/csv;charset=utf-8,${encodeURIComponent(csvWithBom)}`;
        const link = document.createElement('a');
        link.href = url;
        link.download = `claims-report-${this.buildDateStamp()}.csv`;
        link.style.display = 'none';
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
    }

    escapeCsvValue(value) {
        const str = String(value ?? '');
        if (/[",\r\n]/.test(str)) {
            return `"${str.replace(/"/g, '""')}"`;
        }
        return str;
    }

    buildDateStamp() {
        const d = new Date();
        const yyyy = d.getFullYear();
        const mm = String(d.getMonth() + 1).padStart(2, '0');
        const dd = String(d.getDate()).padStart(2, '0');
        return `${yyyy}${mm}${dd}`;
    }

    handleCloseDetail() {
        this.selectedClaimId = null;
    }

    reduceError(err) {
        if (!err) {
            return '';
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
}