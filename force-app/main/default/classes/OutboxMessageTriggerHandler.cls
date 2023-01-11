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

    Message_Subscription__mdt[] subscriptions = OutboxMetadataProvider.getMessageSubscritionMap(
        recordsByMessageType.keySet()
      )
      .values();

    // setup an "outbox" record for each subscription
    List<Subscription_Outbox__c> outboxToInsert = new List<Subscription_Outbox__c>();
    for (Message_Subscription__mdt sub : subscriptions) {
      if (sub.Enabled__c == false) {
        continue;
      }

      for (
        Outbox_Message__c subEvt : recordsByMessageType.get(sub.Message_Definition__r.DeveloperName)
      ) {
        Subscription_Outbox__c outbox = new Subscription_Outbox__c(
          Outbox_Message__c = subEvt.Id,
          Subscription__c = sub.DeveloperName,
          Max_Attempts__c = sub.Max_Attempts__c,
          Application__c = sub.Application__r.DeveloperName
        );
        outboxToInsert.add(outbox);
      }
    }
    insert outboxToInsert;

    OutboxRelayQueuable.enqueue(null);
  }
}
