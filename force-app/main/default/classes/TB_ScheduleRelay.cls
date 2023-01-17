public with sharing class TB_ScheduleRelay implements Schedulable {
    public void execute(SchedulableContext SC) {
        TB_OutboxRelayQueuable.enqueue(null);
    }
}