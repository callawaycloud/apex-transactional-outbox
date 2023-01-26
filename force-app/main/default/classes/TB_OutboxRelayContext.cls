public class TB_OutboxRelayContext {
    
    /**
     * The Outbox record that is being relayed
     * Contains raw information about the subscription and the message
     */
    public TB_Subscription_Outbox__c outbox;

    /**
     * The Configuration field from the subscription after being passed through `JSON.deserializeUntyped`
     */
    public Map<String, Object> subscriptionConfig;
    
    /* 
    * Populated by the IOutboxMessageResolver. Null if no resolver is configured.
    * WARNING: This must be Serializable!
    */ 
    public Object resolvedMessage;

    /* 
    * Generic Object that can be used to store results to be used by an IAfterRelayAction
    * WARNING: This must be Serializable!
    */ 
    public Object relayResult;

    public TB_OutboxRelayContext(
        TB_Subscription_Outbox__c outbox,
        Object resolvedMessage,
        Map<String, Object> subscriptionConfig
    ) {
        this.outbox = outbox;
        this.resolvedMessage = resolvedMessage;
        this.subscriptionConfig = subscriptionConfig;

        //TODO: Should this always reset? Or should we truncate the oldest lines? (split on \n & reverse before saving)
        if (this.outbox.Log__c == null) {
            this.outbox.Log__c = '';
        }
        if (this.outbox.Relay_Attempts__c == null) {
            this.outbox.Relay_Attempts__c = 0;
        }
    }

    public void setAttempt() {
        outbox.Last_Attempt__c = Datetime.Now();
        outbox.Relay_Attempts__c++;
        // reset
        this.outbox.Next_Attempt_Timestamp__c = null;
    }

    public void setResult(Object result) {
        this.relayResult = result;
    }

    public void log(Object trace) {
        outbox.Log__c += System.now() + ': ' + trace.toString() + '\n';
    }

    // will be called by OutboxRelay
    public void setError(Exception e) {
        outbox.Last_Error_Message__c = e.getMessage() + '\n' + e.getStackTraceString();
    }

    // will be called by OutboxRelay
    public void setSuccess() {
        outbox.Completed_Timestamp__c = Datetime.Now();
    }

    public boolean isComplete() {
        return outbox.Completed_Timestamp__c != null;
    }

    public DateTime getNextAttemptTimestamp() {
        return outbox.Next_Attempt_Timestamp__c;
    }

    public void setNextAttemptTimestamp(Datetime nextAttemptTimestamp) {
        outbox.Next_Attempt_Timestamp__c = nextAttemptTimestamp;
    }
}