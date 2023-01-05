# Apex Transactional Outbox

A lightweight framework for external message communication with transactional guarantee.  Ideal for webhooks or other "event driven" communication.

Implemented using a "Transactional Outbox" with support for "fan out" (sending the same message to `n` subscribers).

NOTE: This framework provides a [delivery guarantee of "At Least Once"](https://aws.plainenglish.io/message-delivery-and-processing-guarantees-in-message-driven-and-event-driven-systems-8f17338763c2).  Measures have been put in place to prevent duplicate message delivery, but it is possible in rare circumstances.

## How this works

1. (START TRANSACTION) A process (trigger/event/etc) creates a "Message" (event), specifying it's `type` & `payload`.
1. A "outbox" record is created for each "Subscription" to the message to track the status of the message.  (END TRANSACTION)
1. In a new context, a "relay" runs to process the outbox.  It will attempt to send each pending item in the outbox.
1. If the message is successful, the Outbox Item is marked as complete.  If it fails, the exception is logged, and it will be retried at some point in the future.


## Usage

### Definitions:

- "Message Definition" (`Message_Definition__mdt`): Defines the message type and how it's payload is processed
- "Message Subscription" (`Message_Subscription__mdt`): Defines who will receive each message.
- "Outbox Message" (`Outbox_Message__c`): An instance of message to be sent to each subscriber.  Tracks the payload of the message.
- "Subscription Outbox" (`Subscription_Outbox__c`): The Outbox records tracking that status of the Outbox
- "Outbox Relay" (`OutboxRelayQueuable.cls`): The process responsible for ensuring all outbox messages are sent
- "Relay Client" (`IRelayClient.cls`): The process responsible for getting the message to the subscriber
- "Message Resolver" (`IMessageResolver.cls`): An optional process to "enhance" or modify the message payload at relay runtime.
- "OutboxRelayContext" (`OutboxRelayContext.cls`): The context passed to the "Relay Client" for each outbox item.  Contains the Message Payload, information on previous attempts, ability to log, etc.


### 1. Define the Messages

All events must be defined via `Message_Definition__mdt` with the following properties:

- `DeveloperName`: Required.  This serves as the "Event Type".
- `Message_Resolver__c`: Optional class type used to "enhance" the event message during the message "relay".  See "Runtime Messages Resolution" below.

### 2. Define Subscriptions

Each Event may have multiple subscriptions (`Message_Subscription__mdt`).  For each subscription, an "Outbox" record will be created to ensure the message is successfully sent.  Each subscription has control over how the message is sent.

Properties:

- `Message_Definition__c`: The message definition to send on
- `Enabled__c`: Enables/Disables the subscription. NOTE: This only impacts if Outbox records are created or not.  Items already in the outbox will continue to be relayed regardless of this flag.
- `Relay_Client__c`: The class of the client to instantiate.  Must implement `IOutboxRelayClient`.  The included `GenericHttpRelayClient` will serve the needs of many use cases.
- `Config__c`: (Optional) JSON string that will be added to the context that is passed into the `IOutboxRelayClient.send` method.  Allows a Relay Client to be configured for different subscriptions.  See documentation for `GenericHttpRelayClient` for example.
- `Max_Attempts__c`: Maximum number of times to attempt this message before dead lettering it

### 3. Fire the Message

Construct and insert a `Outbox_Message__c`:

```cs
    Outbox_Message__c[] msgs = new Outbox_Message__c[]{};
    for(Case c : Trigger.new){
        msgs.add(new Outbox_Message__c(
            Type__c='case_created',  // must match a Message_Definition__mdt DeveloperName
            Message__c = c.Id        // whatever you want to send
        ));
    }
    
    insert msgs;
```

When a `Outbox_Message__c` is inserted, a `Subscription_Outbox__c` record will be created for each Active subscription related to the message definition.

## Advanced

### Message "enhancement"

Messages can be "Enhanced" at runtime.  This allows additional capabilities and behavior.

For example, you may choose to only pass a Record Id into a `Event.Message__c`.  A custom `IOutboxMessageResolver` could then be used to query details about the case and construct a totally different payload.  


NOTE: A custom `IRelayClient` also has the opportunity to change the message.  This should be used when different subscription need different messages.  This operation is NOT bulkified!

### Dead-Lettered
A Outbox is "Dead-Lettered" when the "Relay Attempts" exceeds the "Max Attempts" OR the "Manual Dead-Letter" flag has been set.

Once a message has been "Dead-Lettered" relay attempts will stop.  To remove a Outboxed Message from the dead letter the `Subscription_Outbox__c` record to:

- Increase the `Max_Attempts__c` to some value greater than the `Relay_Attempts__c`
- Uncheck `Manual_Deadletter__c`

### Relay Message Order
[TODO]



## Questions

### Why not use Platform Events?

At first glance, platform events (configured to NOT fire "immediate") seems like a great choice to represent the "Message" instead of the Custom Object.  However there are several reasons why we feel "Custom Object" are a better choice:

1. Lifespan: Platform Events only persist for 72 hours max
2. Reliability: Salesforce does NOT guarantee delivery of it's own messages 
3. Observability: Custom Object are much more visible and easier to debug