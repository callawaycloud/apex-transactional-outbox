public class TB_OutboxUtils {
    public static String getClassName(Object h) {
        // thanks https://salesforce.stackexchange.com/a/24002/594
        return String.valueOf(h).split(':')[0].toLowerCase();
    }

    public static Object constructFromName(String className) {
        return constructFromName(className, null);
    }

    public static Object constructFromName(String className, String props) {
        Type t = Type.forName(className);
        if (t == null) {
            throw new TypeException(className + ' does not exist');
        }
        if (props == null) {
            return t.newInstance();
        } else {
            return JSON.deserialize(props, t);
        }
    }

    public static Object parseEnum(string enumString, Type enumType) {
        Type cType = Type.forName(String.format('List<{0}>', new List<String>{ enumType.getName() }));
        return ((List<Object>) JSON.deserialize(String.format('["{0}"]', new List<String>{ enumString }), cType))[0];
    }

    public static boolean isAlreadyQueued(String className) {
        // Query the AsyncApexJob object to find any existing jobs of the specified class
        List<AsyncApexJob> jobs = [
            SELECT Id
            FROM AsyncApexJob
            WHERE JobType = 'Queueable' AND Status = 'Processing' AND ApexClass.Name = :className
        ];

        // Return true if any jobs are found, false otherwise
        return !jobs.isEmpty();
    }

    private class OutboxSort implements Comparable {
        TB_Subscription_Outbox__c record;
        public OutboxSort(TB_Subscription_Outbox__c record) {
            this.record = record;
        }

        public Integer compareTo(Object compareTo) {
            OutboxSort bObject = (OutboxSort) compareTo;
            Integer a = Integer.valueOf(record.Outbox_Message__r.Sequence_Number__c);
            Integer b = Integer.valueOf(bObject.record.Outbox_Message__r.Sequence_Number__c);
            return a - b;
        }
    }

    //seems so inefficent :(
    public static TB_Subscription_Outbox__c[] sortOutboxForProcessing(TB_Subscription_Outbox__c[] records) {
        OutboxSort[] sortingArr = new List<OutboxSort>{};
        for (TB_Subscription_Outbox__c it : records) {
            sortingArr.add(new OutboxSort(it));
        }
        sortingArr.sort();

        TB_Subscription_Outbox__c[] ret = new List<TB_Subscription_Outbox__c>{};
        for (OutboxSort it : sortingArr) {
            ret.add(it.record);
        }
        return ret;
    }
}