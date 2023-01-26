public with sharing class TB_OutboxRelayQueuable implements Queueable, Database.AllowsCallouts {
    DateTime executeStart;
    public TB_OutboxRelayQueuable() {

    }

    /**
     * - Intentionally not dealing with callout Limits... This should maxiumize the work done in a single Async Context
     */
    public void execute(QueueableContext ctx) {
        executeStart = System.now();
        
        // Checkout outbox records with Lock
        List<TB_Subscription_Outbox__c> outboxRecordsUnsorted = [
            SELECT
                Subscription__c,
                Group_Id__c,
                Outbox_Message__c,
                Outbox_Message__r.Sequence_Number__c,
                Outbox_Message__r.Message__c,
                Outbox_Message__r.Type__c,
                Log__c,
                Last_Error_Message__c,
                Relay_Attempts__c,
                Completed_Timestamp__c,
                Next_Attempt_Timestamp__c
            FROM TB_Subscription_Outbox__c
            WHERE Completed_Timestamp__c = NULL 
            AND Dead_Lettered__c = FALSE
            AND (Next_Attempt_Timestamp__c <= :executeStart OR Next_Attempt_Timestamp__c = NULL)
            FOR UPDATE
        ];

        Set<String> deadGroupIds = getDeadGroups(outboxRecordsUnsorted);

        // Sort by Sequence Number
        List<TB_Subscription_Outbox__c> outboxRecords = TB_OutboxUtils.sortOutboxForProcessing(outboxRecordsUnsorted);

        // group messages by type to resolve
        Map<String, TB_Outbox_Message__c[]> msgsByType = new Map<String, TB_Outbox_Message__c[]>();
        for (TB_Subscription_Outbox__c item : outboxRecords) {
            if (!msgsByType.containsKey(item.Outbox_Message__r.Type__c)) {
                msgsByType.put(item.Outbox_Message__r.Type__c, new List<TB_Outbox_Message__c>{});
            }

            msgsByType.get(item.Outbox_Message__r.Type__c).add(item.Outbox_Message__r);
        }

        // transform DTO's
        Map<Id, Object> allresolvedMessages = resolveMessages(msgsByType);

        Map<String, TB_Message_Subscription__mdt> subscriptionsMetadataMap = TB_OutboxMetadataProvider.getMessageSubscritionMap(
            msgsByType.keySet()
        );

        Map<String, TB_IAfterRelayAction> afterRelayActions = TB_OutboxMetadataProvider.getAfterRelayActionsMap(
            subscriptionsMetadataMap.values()
        );

        OutboxFinalizer finalizer = new OutboxFinalizer(afterRelayActions);
        System.attachFinalizer(finalizer);

        // Process Each Outbox
        for (TB_Subscription_Outbox__c item : outboxRecords) {
            //check if item is part of a "deadlettered group"
            if (item.Group_Id__c != null && deadGroupIds.contains(item.Group_Id__c)) {
                continue;
            }
            TB_Message_Subscription__mdt subDef = subscriptionsMetadataMap.get(item.Subscription__c);
            Map<String, Object> subConfig = TB_OutboxMetadataProvider.getSubscriptionConfig(subDef);
            Object resolvedEvt = allresolvedMessages.get(item.Outbox_Message__c);
            TB_OutboxRelayContext obCtx = new TB_OutboxRelayContext(item, resolvedEvt, subConfig);

            try {
                obCtx.setAttempt();
                TB_IOutboxRelayClient client = TB_OutboxMetadataProvider.getSubscriptionRelayClient(subDef);
                client.send(obCtx);
                obCtx.setSuccess();
            } catch (Exception e) {
                obCtx.setError(e);
                if (item.Group_Id__c != null) {
                    // cannot continue processing any other messages in this group
                    deadGroupIds.add(item.Group_Id__c);
                }
                // set next attempt backoff (if not already set by client)
                if(obCtx.getNextAttemptTimestamp() == null){
                    obCtx.setNextAttemptTimestamp(TB_OutboxMetadataProvider.getSubscriptionNextAttemptTimeStamp(subDef, (Integer) obCtx.outbox.Relay_Attempts__c));
                }
            } finally {
                //TODO: should this be added before? What happens if limit exception is thrown?
                finalizer.addResult(obCtx);
            }
        }
        // attempt to save results with Lock
        finalizer.save();
    }

    /**
     * Dead groups are subscription message groups which have an item in the dead letter queue.
     * We cannot continue processing the rest of the group until resolved
     */
    private Set<String> getDeadGroups(List<TB_Subscription_Outbox__c> outboxRecords) {
        Set<String> activeGroupIds = new Set<String>();
        for (TB_Subscription_Outbox__c item : outboxRecords) {
            if (item.Group_Id__c != null) {
                activeGroupIds.add(item.Group_Id__c);
            }
        }

        Set<String> deadGroups = new Set<String>();
        if (activeGroupIds.size() > 0) {
            for (TB_Subscription_Outbox__c item : [
                SELECT Group_Id__c
                FROM TB_Subscription_Outbox__c
                WHERE (Dead_Lettered__c = TRUE OR Next_Attempt_Timestamp__c > :executeStart) AND Group_Id__c IN :activeGroupIds
            ]) {
                deadGroups.add(item.Group_Id__c);
            }
        }

        return deadGroups;
    }

    /**
     * Bulk Resolve Messages.
     */
    private static Map<Id, Object> resolveMessages(Map<String, TB_Outbox_Message__c[]> msgsByType) {
        Map<String, TB_Message_Definition__mdt> definitionsByLabel = TB_OutboxMetadataProvider.getMessageDefintionMap();

        //resolve Message DTO
        Map<Id, Object> allresolvedMessages = new Map<Id, Object>();
        for (String msgType : msgsByType.keySet()) {
            TB_Message_Definition__mdt def = definitionsByLabel.get(msgType);
            TB_Outbox_Message__c[] msgs = msgsByType.get(msgType);
            if (def.Message_Resolver__c != null) {
                TB_IOutboxMessageResolver resolver = TB_OutboxMetadataProvider.getMessageResolver(def);
                Map<Id, Object> resolvedMessages = resolver.resolveMessages(msgs);
                allresolvedMessages.putAll(resolvedMessages);
            }
        }
        return allresolvedMessages;
    }

    /**
     * Finalizer repsonsible for tracking state of outbox requests and persisting it.
     * Even if we run into a limit exception, the finalizer should ensure the outbox results get persisted.
     * WARNING: There is perhaps a small chance that a new TB_OutboxRelayQueuable job could start up in the time between the origional job and the finalizer execution...
     */
    private class OutboxFinalizer implements Finalizer {
        // Id -> Success Timestamp
        private Map<Id, TB_OutboxRelayContext> results;
        private Set<Id> saved;

        private Map<String, TB_IAfterRelayAction> afterRelayActions = new Map<String, TB_IAfterRelayAction>();

        private OutboxFinalizer(Map<String, TB_IAfterRelayAction> afterRelayActions) {
            this.afterRelayActions = afterRelayActions;
            saved = new Set<Id>();
            results = new Map<Id, TB_OutboxRelayContext>();
        }

        public void addResult(TB_OutboxRelayContext ctx) {
            results.put(ctx.outbox.id, ctx);
        }

        public Map<Id, TB_OutboxRelayContext> getUnsavedResults() {
            Map<Id, TB_OutboxRelayContext> unsaved = new Map<Id, TB_OutboxRelayContext>(results);
            for (Id savedId : saved) {
                unsaved.remove(savedId);
            }
            return unsaved;
        }

        /**
         * Save Result and remove them if successful
         */
        public void save() {
            Map<Id, TB_OutboxRelayContext> unsaved = getUnsavedResults();
            System.debug('Attempting to save results: ' + unsaved.size());

            List<TB_Subscription_Outbox__c> outboxRecordsToUpdate = new List<TB_Subscription_Outbox__c>();
            for (TB_OutboxRelayContext ctx : unsaved.values()) {
                outboxRecordsToUpdate.add(ctx.outbox);
            }

            // Remove all successes from the state
            List<Database.SaveResult> results = Database.update(outboxRecordsToUpdate, false);
            for (Database.SaveResult sr : results) {
                if (sr.isSuccess()) {
                    saved.add(sr.getId());
                } else {
                    System.debug('Failed to save result');
                    System.debug(sr.getErrors());
                }
            }
        }

        public void execute(FinalizerContext ctx) {
            // Should we get a new query lock?
            Exception e = ctx.getException();
            if (e != null) {
                System.debug('Queueable Terminated with Error! ' + e.getMessage() + '\\n' + e.getStackTraceString());
            }

            save();

            try {
                TB_Subscription_Outbox__c[] activeOutboxItems = [
                    SELECT Id
                    FROM TB_Subscription_Outbox__c
                    WHERE Completed_Timestamp__c = NULL AND Dead_Lettered__c = FALSE
                    LIMIT 1
                ];
                // more work to be done
                if (activeOutboxItems.size() > 0) {
                    TB_OutboxRelayQueuable.enqueue(ctx.getAsyncApexJobId());
                }
            } catch (Exception ex) {
                System.debug('Exception prevented enqueue TB_OutboxRelayQueuable');
                System.debug(ex);
            }
            executeAfterActions();
        }

        /** Run all After Relay Actions */
        private void executeAfterActions(){
            if(afterRelayActions.isEmpty()){
                return;
            }

            //group results by subscription__c
            Map<String, List<TB_OutboxRelayContext>> resultsBySubscription = new Map<String, List<TB_OutboxRelayContext>>();
            for (TB_OutboxRelayContext item : results.values()) {
                if (resultsBySubscription.containsKey(item.outbox.Subscription__c)) {
                    resultsBySubscription.get(item.outbox.Subscription__c).add(item);
                } else {
                    resultsBySubscription.put(item.outbox.Subscription__c, new List<TB_OutboxRelayContext>{ item });
                }
            }

            //run each after relay action
            for (String subscriptionKey : afterRelayActions.keySet()) {
                try{
                    TB_IAfterRelayAction action = afterRelayActions.get(subscriptionKey);
                    if(action != null){
                        action.execute(resultsBySubscription.get(subscriptionKey));
                    }
                }catch(Exception e){
                    // eat the exception.  They should have handled it themselves :(
                    System.debug('Exception executing after relay action for subscription ' + subscriptionKey);
                    System.debug(e);
                }
            }
        }
    }

    @testvisible
    static boolean alreadyQueuedInContext = false;
    public static void enqueue(Id currentAsyncJobId) {
        if (alreadyQueuedInContext) {
            System.debug('Already enqueue in this context');
            return;
        }

        Integer maxAllowedJobs = System.isBatch() || System.isFuture() || System.isQueueable() ? 1 : Limits.getLimitQueueableJobs();

        if (Limits.getQueueableJobs() >= maxAllowedJobs) {
            System.debug('Unable to enqueue TB_OutboxRelayQueuable due to limits. Max Allowed Jobs: ' + maxAllowedJobs);
            return;
        }

        AsyncApexJob[] currentJobs = [
            SELECT Id, ApexClass.Name, ExtendedStatus, Status
            FROM AsyncApexJob
            WHERE
                JobType = 'Queueable'
                AND ApexClass.Name = 'TB_OutboxRelayQueuable'
                AND Status IN ('Preparing', 'Processing', 'Queued')
                AND Id != :currentAsyncJobId
            ORDER BY CreatedDate DESC
        ];

        if (currentJobs.size() > 0) {
            System.debug('Relay Job already in progress: ' + currentJobs[0].Id);
            return;
        }

        System.enqueueJob(new TB_OutboxRelayQueuable());
        alreadyQueuedInContext = true;
    }
}