public with sharing class OutboxMessageTriggerHandler {
  public void handle() {
    Map<String, List<Outbox_Message__c>> recordsByMessageType = new Map<String, List<Outbox_Message__c>>();
    for (Outbox_Message__c evt : (List<Outbox_Message__c>) Trigger.new) {
      // group evts by type
      String evtType = evt.Type__c;
      List<Outbox_Message__c> evts = recordsByMessageType.get(evtType);
      if (evts == null) {
        evts = new List<Outbox_Message__c>();
        recordsByMessageType.put(evtType, evts);
      }
      evts.add(evt);
    }

    // setup an "outbox" record for each subscription
    Message_Subscription__mdt[] subscriptions = [
      SELECT DeveloperName, QualifiedApiName, Message_Definition__r.DeveloperName, Max_Attempts__c
      FROM Message_Subscription__mdt
      WHERE Message_Definition__r.DeveloperName IN :recordsByMessageType.keySet()
    ];

    List<Subscription_Outbox__c> outboxToInsert = new List<Subscription_Outbox__c>();
    for (Message_Subscription__mdt sub : subscriptions) {
      for (Outbox_Message__c subEvt : recordsByMessageType.get(sub.Message_Definition__r.DeveloperName)) {
        Subscription_Outbox__c outbox = new Subscription_Outbox__c(
          Outbox_Message__c = subEvt.Id,
          Subscription__c = sub.DeveloperName,
          Max_Attempts__c = sub.Max_Attempts__c
        );
        outboxToInsert.add(outbox);
      }
    }
    insert outboxToInsert;

    // already in batch or future context... Will have to get picked up by scheduled apex cleanup job?  
    // Or we could fire an immediate message to kick off the batch?
    // if(!System.isFuture() && !System.isBatch()){
    //     // if (outboxToInsert.size() < 50) {
    //     //     OutboxRelay.executeRelayFuture(Trigger.newMap.keySet());
    //     // }else{
    //     //     System.scheduleBatch(new OutboxRelayBatch(), 'outbox:near-real-time', 1);
    //     // }
        
    // }
    if(Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()){
      System.enqueueJob(new OutboxRelayQueuable());
    }
    
  }

}
