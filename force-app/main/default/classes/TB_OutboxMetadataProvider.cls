public class TB_OutboxMetadataProvider {
    @testVisible
    static TB_Message_Definition__mdt[] msgDefinitions;

    public static Map<String, TB_Message_Definition__mdt> getMessageDefintionMap() {
        if (msgDefinitions == null) {
            msgDefinitions = [
                SELECT DeveloperName, QualifiedApiName, Message_Resolver__c
                FROM TB_Message_Definition__mdt
            ];
        }

        Map<String, TB_Message_Definition__mdt> definitionsByLabel = new Map<String, TB_Message_Definition__mdt>();
        for (TB_Message_Definition__mdt def : msgDefinitions) {
            definitionsByLabel.put(def.DeveloperName, def);
        }
        return definitionsByLabel;
    }

    @testVisible
    static TB_Message_Subscription__mdt[] subscriptions;
    public static Map<String, TB_Message_Subscription__mdt> getMessageSubscritionMap(Set<String> msgTypes) {
        if (subscriptions == null) {
            subscriptions = [
                SELECT
                    DeveloperName,
                    Application__r.DeveloperName,
                    Message_Definition__r.DeveloperName,
                    Relay_Client__c,
                    Config__c,
                    Max_Attempts__c,
                    Enabled__c,
                    After_Relay_Action__c,
                    Isolate_Relay__c,
                    Retry_Backoff__c
                FROM TB_Message_Subscription__mdt
            ];
        }

        Map<String, TB_Message_Subscription__mdt> subscriptionsByLabel = new Map<String, TB_Message_Subscription__mdt>();
        for (TB_Message_Subscription__mdt sub : subscriptions) {
            if (msgTypes.contains(sub.Message_Definition__r.DeveloperName)) {
                subscriptionsByLabel.put(sub.DeveloperName, sub);
            }
        }
        return subscriptionsByLabel;
    }

    static Map<String, Map<String, Object>> configCache = new Map<String, Map<String, Object>>();
    public static Map<String, Object> getSubscriptionConfig(TB_Message_Subscription__mdt subscriptionDef) {
        if (configCache.containsKey(subscriptionDef.DeveloperName)) {
            return configCache.get(subscriptionDef.DeveloperName);
        }

        Map<String, Object> config = new Map<String, Object>();
        if (subscriptionDef.Config__c != null) {
            config = (Map<String, Object>) JSON.deserializeUntyped(subscriptionDef.Config__c);
        }
        configCache.put(subscriptionDef.DeveloperName, config);
        return config;
    }

    static Map<String, Integer[]> retryBackOffCache = new Map<String, Integer[]>();
    public static DateTime getSubscriptionNextAttemptTimeStamp(TB_Message_Subscription__mdt subscriptionDef, Integer attempt) {
        if(subscriptionDef.Retry_BackOff__c == null) {
            return null;
        }

        Integer[] backoffList = retryBackOffCache.get(subscriptionDef.DeveloperName);

        // setup backoff list
        if (backoffList == null) {
            backoffList = new Integer[]{};
            for(String backOff : subscriptionDef.Retry_BackOff__c.split(',')){
                backoffList.add(Integer.valueOf(backOff));
            }
            retryBackOffCache.put(subscriptionDef.DeveloperName, backoffList);
        }

        // get current backoff and return new date that many minutes in the future
        return System.now().addMinutes(backoffList[Math.min(backoffList.size() - 1, attempt - 1)]);
    }

    static Map<String, TB_IOutboxRelayClient> clientCache = new Map<String, TB_IOutboxRelayClient>();
    public static TB_IOutboxRelayClient getSubscriptionRelayClient(TB_Message_Subscription__mdt subscriptionDef) {
        if (clientCache.containsKey(subscriptionDef.DeveloperName)) {
            return clientCache.get(subscriptionDef.DeveloperName);
        }

        TB_IOutboxRelayClient client = (TB_IOutboxRelayClient) TB_OutboxUtils.constructFromName(
            subscriptionDef.Relay_Client__c
        );
        clientCache.put(subscriptionDef.DeveloperName, client);
        return client;
    }

    public static TB_IOutboxMessageResolver getMessageResolver(TB_Message_Definition__mdt def) {
        return (TB_IOutboxMessageResolver) TB_OutboxUtils.constructFromName(def.Message_Resolver__c);
    }

    public static Map<String, TB_IAfterRelayAction> getAfterRelayActionsMap(TB_Message_Subscription__mdt[] subsMdt) {
        Map<String, TB_IAfterRelayAction> afterRelayActions = new Map<String, TB_IAfterRelayAction>();
        for (TB_Message_Subscription__mdt sub : subsMdt) {
            if (sub.After_Relay_Action__c != null) {
                afterRelayActions.put(sub.DeveloperName, (TB_IAfterRelayAction) TB_OutboxUtils.constructFromName(sub.After_Relay_Action__c));
            }
        }
        return afterRelayActions;
    }
}
