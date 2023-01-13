public class CaseCreatedMessageResolver implements TB_IOutboxMessageResolver {
    public Map<Id, Case> resolveMessages(TB_Outbox_Message__c[] messages) {
        Set<Id> caseIds = new Set<Id>();
        for (TB_Outbox_Message__c evt : messages) {
            caseIds.add(evt.Message__c);
        }

        Map<Id, Case> cases = new Map<Id, Case>([SELECT Id, Status FROM Case WHERE Id IN :caseIds]);

        Map<Id, Case> resolved = new Map<Id, Case>();
        for (TB_Outbox_Message__c msg : messages) {
            resolved.put(msg.Id, cases.get(msg.Message__c));
        }
        return resolved;
    }
}