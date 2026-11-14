import { LightningElement, api } from 'lwc';
import submitStatement from '@salesforce/apex/InvImportActions.submit';

export default class InvParseStatement extends LightningElement {
    @api runId;
    busy = false;
    message = '';
    password = '';
    handlePassword(event) { this.password = event.target.value; }
    async submit() {
        this.busy = true;
        try {
            const status = await submitStatement({ runId: this.runId, password: this.password });
            this.message = `Import status: ${status}. Open the import record to review the result.`;
        } catch (error) {
            this.message = error.body?.message || 'Parsing could not start. Retry from the import record.';
        } finally {
            this.password = '';
            this.template.querySelector('lightning-input').value = '';
            this.busy = false;
        }
    }
    disconnectedCallback() { this.password = ''; }
}
