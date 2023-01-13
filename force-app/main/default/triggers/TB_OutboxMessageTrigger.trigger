/**
 * Initilizes Outbox Records for Each subscription of an message
 */
trigger TB_OutboxMessageTrigger on TB_Outbox_Message__c(after insert) {
    new TB_OutboxMessageTriggerHandler().handle();
}