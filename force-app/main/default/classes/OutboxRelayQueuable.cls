public with sharing class OutboxRelayQueuable implements Queueable, Database.AllowsCallouts {
  public OutboxRelayQueuable() {
  }

  /**
   * - Intentionally not dealing with callout Limits... This should maxiumize the work done in a single Async Context
   */
  public void execute(QueueableContext ctx) {
    //TODO: confirm "FOR UPDATE" actually "locks" these records?
    // Should be Locked until at least the transactional Finalizer?
    List<Subscription_Outbox__c> outboxRecordsUnsorted = [
      SELECT
        Subscription__c,
        Group_Id__c,
        Outbox_Message__c,
        Outbox_Message__r.Sequence_Number__c,
        Outbox_Message__r.Message__c,
        Outbox_Message__r.Type__c,
        Log__c,
        Last_Error_Message__c,
        Relay_Attempts__c
      FROM Subscription_Outbox__c
      WHERE Completed_Timestamp__c = NULL AND Dead_Lettered__c = FALSE
      FOR UPDATE
    ];

    Set<String> deadGroupIds = getDeadGroups(outboxRecordsUnsorted);

    // Sort by Sequence Number
    List<Subscription_Outbox__c> outboxRecords = OutboxUtils.sortOutboxForProcessing(
      outboxRecordsUnsorted
    );

    OutboxFinalizer finalizer = new OutboxFinalizer(outboxRecords.size());
    System.attachFinalizer(finalizer);

    // group messages by type to resolve
    Map<String, Outbox_Message__c[]> msgsByType = new Map<String, Outbox_Message__c[]>();
    for (Subscription_Outbox__c item : outboxRecords) {
      if (!msgsByType.containsKey(item.Outbox_Message__r.Type__c)) {
        msgsByType.put(item.Outbox_Message__r.Type__c, new List<Outbox_Message__c>{});
      }

      msgsByType.get(item.Outbox_Message__r.Type__c).add(item.Outbox_Message__r);
    }

    // transform DTO's
    Map<Id, Object> allresolvedMessages = resolveMessages(msgsByType);

    Map<String, Message_Subscription__mdt> subscriptionsMetadataMap = OutboxMetadataProvider.getMessageSubscritionMap(
      msgsByType.keySet()
    );

    // Process Each Outbox
    for (Subscription_Outbox__c item : outboxRecords) {
      //check if item is part of a "deadlettered group"
      if (item.Group_Id__c != null && deadGroupIds.contains(item.Group_Id__c)) {
        continue;
      }
      Message_Subscription__mdt subDef = subscriptionsMetadataMap.get(item.Subscription__c);
      Map<String, Object> subConfig = OutboxMetadataProvider.getSubscriptionConfig(subDef);
      Object resolvedEvt = allresolvedMessages.get(item.Outbox_Message__c);
      OutboxRelayContext obCtx = new OutboxRelayContext(item, resolvedEvt, subConfig);

      try {
        obCtx.setAttempt();
        IOutboxRelayClient carrier = OutboxMetadataProvider.getSubscriptionRelayClient(subDef);
        carrier.send(obCtx);
        obCtx.setSuccess();
      } catch (Exception e) {
        obCtx.setError(e);
        if (item.Group_Id__c != null) {
          // cannot continue processing any other messages in this group
          deadGroupIds.add(item.Group_Id__c);
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
  private static Set<String> getDeadGroups(List<Subscription_Outbox__c> outboxRecords) {
    Set<String> activeGroupIds = new Set<String>();
    for (Subscription_Outbox__c item : outboxRecords) {
      if (item.Group_Id__c != null) {
        activeGroupIds.add(item.Group_Id__c);
      }
    }

    Set<String> deadGroups = new Set<String>();
    if (activeGroupIds.size() > 0) {
      for (Subscription_Outbox__c item : [
        SELECT Group_Id__c
        FROM Subscription_Outbox__c
        WHERE Dead_Lettered__c = TRUE AND Group_Id__c IN :activeGroupIds
      ]) {
        deadGroups.add(item.Group_Id__c);
      }
    }

    return deadGroups;
  }

  /**
   * Bulk Resolve Messages.
   */
  private static Map<Id, Object> resolveMessages(Map<String, Outbox_Message__c[]> msgsByType) {
    Map<String, Message_Definition__mdt> definitionsByLabel = OutboxMetadataProvider.getMessageDefintionMap(
      msgsByType.keySet()
    );

    //resolve Message DTO
    Map<Id, Object> allresolvedMessages = new Map<Id, Object>();
    for (String msgType : msgsByType.keySet()) {
      Message_Definition__mdt def = definitionsByLabel.get(msgType);
      Outbox_Message__c[] msgs = msgsByType.get(msgType);
      if (def.Message_Resolver__c != null) {
        IOutboxMessageResolver resolver = OutboxMetadataProvider.getMessageResolver(def);
        Map<Id, Object> resolvedMessages = resolver.resolveMessages(msgs);
        allresolvedMessages.putAll(resolvedMessages);
      }
    }
    return allresolvedMessages;
  }

  /**
   * Finalizer repsonsible for tracking state of outbox requests and persisting it.
   * Even if we run into a limit exception, the finalizer should ensure the outbox results get persisted.
   * WARNING: There is perhaps a small chance that a new OutboxRelayQueuable job could start up in the time between the origional job and the finalizer execution...
   */
  private class OutboxFinalizer implements Finalizer {
    private Integer outboxCount;
    // Id -> Success Timestamp
    private Map<Id, OutboxRelayContext> results;
    private Set<Id> saved;
    private OutboxFinalizer(Integer outboxCount) {
      this.outboxCount = outboxCount;
      saved = new Set<Id>();
      results = new Map<Id, OutboxRelayContext>();
    }

    public void addResult(OutboxRelayContext ctx) {
      results.put(ctx.outbox.id, ctx);
    }

    public Map<Id, OutboxRelayContext> getUnsavedResults() {
      Map<Id, OutboxRelayContext> unsaved = new Map<Id, OutboxRelayContext>(results);
      for (Id savedId : saved) {
        unsaved.remove(savedId);
      }
      return unsaved;
    }

    /**
     * Save Result and remove them if successful
     */
    public void save() {
      Map<Id, OutboxRelayContext> unsaved = getUnsavedResults();
      System.debug('Attempting to save results: ' + unsaved.size());

      List<Subscription_Outbox__c> outboxRecordsToUpdate = new List<Subscription_Outbox__c>();
      for (OutboxRelayContext ctx : unsaved.values()) {
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
        System.debug(
          'Queueable Terminated with Error! ' + e.getMessage() + '\\n' + e.getStackTraceString()
        );
      }

      save();

      try {
        Subscription_Outbox__c[] activeOutboxItems = [
          SELECT Id
          FROM Subscription_Outbox__c
          WHERE Completed_Timestamp__c = NULL AND Dead_Lettered__c = FALSE
          LIMIT 1
        ];
        // more work to be done
        if (activeOutboxItems.size() > 0) {
          OutboxRelayQueuable.enqueue(ctx.getAsyncApexJobId());
        }
      } catch (Exception ex) {
        System.debug('Exception prevented enqueue OutboxRelayQueuable');
        System.debug(ex);
      }
    }
  }

  private static boolean alreadyQueuedInContext = false;
  public static void enqueue(Id currentAsyncJobId) {
    if (alreadyQueuedInContext) {
      System.debug('Already enqueue in this context');
      return;
    }

    if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs()) {
      System.debug('Unable to enqueue OutboxRelayQueuable due to limits');
      return;
    }

    AsyncApexJob[] currentJobs = [
      SELECT Id, ApexClass.Name, ExtendedStatus, Status
      FROM AsyncApexJob
      WHERE
        JobType = 'Queueable'
        AND ApexClass.Name = 'OutboxRelayQueuable'
        AND Status IN ('Preparing', 'Processing', 'Queued')
        AND Id != :currentAsyncJobId
      ORDER BY CreatedDate DESC
    ];

    if (currentJobs.size() > 0) {
      System.debug('Relay Job already in progress: ' + currentJobs[0].Id);
      return;
    }

    System.enqueueJob(new OutboxRelayQueuable());
    alreadyQueuedInContext = true;
  }
}
