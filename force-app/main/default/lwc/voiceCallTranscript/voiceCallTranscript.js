import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getTranscript from '@salesforce/apex/CallTranscriptController.getTranscript';

export default class VoiceCallTranscript extends LightningElement {
    @api recordId;
    @api conversationId;

    isLoading = true;
    errorMessage;
    searchTerm = '';

    _wiredResult;
    _entries = [];
    _conversation;
    _voiceCall;
    _recordings = [];

    get effectiveRecordId() {
        return this.conversationId || this.recordId;
    }

    @wire(getTranscript, { recordId: '$effectiveRecordId' })
    wiredTranscript(result) {
        this._wiredResult = result;
        this.isLoading = true;
        const { data, error } = result;
        if (data) {
            this._conversation = data.conversation;
            this._voiceCall = data.voiceCall;
            this._recordings = data.recordings || [];
            this._entries = (data.entries || []).map((e, idx) => this.decorateEntry(e, idx));
            this.errorMessage = undefined;
            this.isLoading = false;
        } else if (error) {
            this._entries = [];
            this._recordings = [];
            this._voiceCall = undefined;
            this.errorMessage =
                (error && error.body && error.body.message) ||
                error.message ||
                'Unable to load the transcript.';
            this.isLoading = false;
        }
    }

    decorateEntry(entry, idx) {
        const actor = (entry.actorType || '').toLowerCase();
        const isAgent =
            entry.actorType &&
            ['agent', 'bot', 'system', 'einstein', 'ai'].some((a) => actor.includes(a));
        const initials = this.initialsFromSpeaker(entry.speaker);
        return {
            ...entry,
            id: entry.id || `entry-${idx}`,
            rowClass: isAgent ? 'vct-row vct-row--agent' : 'vct-row vct-row--customer',
            bubbleClass: isAgent ? 'vct-bubble vct-bubble--agent' : 'vct-bubble vct-bubble--customer',
            roleLabel: isAgent ? 'Agent' : 'Caller',
            initials
        };
    }

    initialsFromSpeaker(speaker) {
        if (!speaker) {
            return '?';
        }
        const parts = speaker.trim().split(/\s+/).filter(Boolean);
        if (parts.length >= 2) {
            return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
        }
        return speaker.slice(0, 2).toUpperCase();
    }

    get hasEntries() {
        return !this.isLoading && !this.errorMessage && this._entries.length > 0;
    }

    get isEmpty() {
        return !this.isLoading && !this.errorMessage && this._entries.length === 0;
    }

    get filteredEntries() {
        if (!this.searchTerm) {
            return this._entries;
        }
        const term = this.searchTerm.toLowerCase();
        return this._entries.filter(
            (e) =>
                (e.text && e.text.toLowerCase().includes(term)) ||
                (e.speaker && e.speaker.toLowerCase().includes(term))
        );
    }

    get noSearchResults() {
        return this.searchTerm && this.filteredEntries.length === 0;
    }

    get hasRecordings() {
        return this._recordings && this._recordings.length > 0;
    }

    get recordingCards() {
        return (this._recordings || []).map((r, i) => ({
            key: r.id || `rec-${i}`,
            title: r.name || `Recording ${i + 1}`,
            subtitle: this.formatRecordingMeta(r),
            audioSrc: r.mediaContentId ? this.buildDownloadUrl(r.mediaContentId) : null,
            fileUrl: r.mediaContentId ? `/lightning/r/ContentDocument/${r.mediaContentId}/view` : null
        }));
    }

    buildDownloadUrl(contentDocumentId) {
        if (!contentDocumentId) {
            return null;
        }
        return `/sfc/servlet.shepherd/document/download/${contentDocumentId}`;
    }

    formatRecordingMeta(r) {
        const parts = [];
        if (r.durationSeconds != null) {
            parts.push(`${r.durationSeconds}s`);
        }
        if (r.uploadedAt) {
            parts.push(new Date(r.uploadedAt).toLocaleString());
        }
        return parts.length ? parts.join(' · ') : 'Voice recording';
    }

    get headerSubtitle() {
        const parts = [];
        const vc = this._voiceCall;
        if (vc && vc.callStart) {
            parts.push(`Started ${new Date(vc.callStart).toLocaleString()}`);
        } else if (this._conversation && this._conversation.StartTime) {
            parts.push(`Started ${new Date(this._conversation.StartTime).toLocaleString()}`);
        }
        if (vc && vc.fromPhone) {
            parts.push(`From ${vc.fromPhone}`);
        }
        if (vc && vc.toPhone) {
            parts.push(`To ${vc.toPhone}`);
        }
        parts.push(`${this._entries.length} transcript lines`);
        if (this._recordings.length) {
            parts.push(`${this._recordings.length} recording${this._recordings.length === 1 ? '' : 's'}`);
        }
        return parts.join(' · ');
    }

    get showRecordingSection() {
        return !this.isLoading && !this.errorMessage && this.hasRecordings;
    }

    handleSearch(event) {
        this.searchTerm = event.target.value || '';
    }

    handleRefresh() {
        refreshApex(this._wiredResult);
    }

    handleCopy() {
        if (!this._entries.length) {
            return;
        }
        const text = this._entries
            .map((e) => {
                const time = e.timestamp ? new Date(e.timestamp).toLocaleTimeString() : '';
                return `[${time}] ${e.speaker}: ${e.text}`;
            })
            .join('\n');

        if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(text).then(
                () => this.toast('Copied', 'Transcript copied to clipboard.', 'success'),
                () => this.toast('Copy failed', 'Unable to copy transcript.', 'error')
            );
        } else {
            this.toast('Copy unavailable', 'Clipboard API not available.', 'warning');
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}