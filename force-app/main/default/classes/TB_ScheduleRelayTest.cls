@isTest
public class TB_ScheduleRelayTest {
    @isTest
    private static void testSchedulable() {
        Test.startTest();
        TB_ScheduleRelay scheduledRelay = new TB_ScheduleRelay();
        String chron = '0 0 23 * * ?';
        System.schedule('Test Sched', chron, scheduledRelay);
        Test.stopTest();
    }
}