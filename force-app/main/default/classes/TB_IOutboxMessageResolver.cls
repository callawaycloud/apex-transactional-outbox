public interface TB_IOutboxMessageResolver {
    /**
     * Returns a map of resolved Messages where the key is the related Message Id
     */
    Map<Id, Object> resolveMessages(TB_Outbox_Message__c[] messages);
}