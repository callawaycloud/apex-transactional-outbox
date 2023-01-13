# Apex Transactional Outbox

A lightweight framework for external message communication with transactional guarantee. Ideal for webhooks or other "directed event driven communication".

Implemented using a ["Transactional Outbox"](https://microservices.io/patterns/data/transactional-outbox.html) pattern.

## Features:

-   **Transactional Guarantee**: Messages cannot be "lost" if they fail delivery `*`
-   **Fan Out**: Support delivering a message to `n` subscribers
-   **Low Code**: Many use-cases can be achieved with 100% configuration or only a few lines of additional code
-   **Automatic Retries**: Control over automatic retries
-   **Efficient**: Carefully optimized in it's consumption of limits (Daily AsyncJobs, SOQL Queries, DML)
-   **"Dead-Lettering"**: Message "Dead-lettering" to prevent endless retries and make it easy to find failures
-   **"Message Groups"**: support for sequential delivery of a set of messages when required
-   **Logging**: Built-in logging capabilities make it easy to observe when things go wrong

### Planned improvements:

-   **Automatic Circuit Breaking**: If a message to be delivered to a subscription, a "Circuit Breaker" can be triggered to prevent other attempts for a period of time
-   **Retry Back-off**: Configure retry back-offs to give the downstream system time to come back up
-   **Message TTL (time-to-live)**: Automatically remove messages & outbox records after they have been completed

*   `*`: This framework provides a [delivery guarantee of "At Least Once"](https://aws.plainenglish.io/message-delivery-and-processing-guarantees-in-message-driven-and-event-driven-systems-8f17338763c2). Measures have been put in place to prevent duplicate message delivery, but it is possible in rare circumstances.\*

## Framework Design

![Transactional Outbox Abstraction](https://user-images.githubusercontent.com/5217568/211720999-0ba7a702-278e-471f-a1ca-e68a4ac30faa.png)

_The above diagram is a conceptual abstraction for the key aspects of the framework_

1.  Some _"Domain Event"_ (trigger, event, flow, etc) creates a "Message" (eg: event), specifying it's `type` & `payload`.
    -   A "outbox" record is created for each "Subscription" to the Message to track the status of the message delivery.
    -   These records are all part of the atomic "Domain Transaction"
2.  In a new context (in "Near Real Time"), the "Outbox Relay" runs to process the outbox. It will attempt to send each pending item in the outbox.
3.  If the message is successful, the "Outbox" record is marked as complete. If it fails, the exception is logged, and it will be retried at some point in the future. If failures continued, it will be "Dead-Lettered" for manual review.

### Definitions:

-   **Application** (`TB_Application__mdt`): An system/entity that receives messages. Used to group subscriptions76.
-   **Message Definition** (`TB_Message_Definition__mdt`): Defines the message type and how it's payload is processed
-   **Message Subscription** (`TB_Message_Subscription__mdt`): Defines who will receive each message.
-   **Outbox Message** (`TB_Outbox_Message__c`): An instance of message to be sent to each subscriber. Tracks the payload of the message.
-   **Subscription Outbox** (`TB_Subscription_Outbox__c`): The Outbox records tracking that status of the Outbox
-   **Outbox Relay** (`TB_OutboxRelayQueuable.cls`): The process responsible for ensuring all outbox messages are sent
-   **Relay Client** (`TB_IRelayClient.cls`): The process responsible for getting the message to the subscriber
-   **Message Resolver** (`TB_IMessageResolver.cls`): An optional process to "enhance" or modify the message payload at relay runtime.
-   **TB_OutboxRelayContext** (`TB_OutboxRelayContext.cls`): The context passed to the "Relay Client" for each outbox item. Contains the Message Payload, information on previous attempts, ability to log, etc.

## Usage

### 1. Create an "Application"

The Application serves as the container for a set of subscriptions. How you split out multiple Applications depends on the scenario, but typically you would have 1 Application per external service.

### 1. Define a "Message"

All messages must be defined via `TB_Message_Definition__mdt` with the following properties:

-   Message Type (`Label`): Required. Recommended to use a pattern like `{object}_{event}`.
-   `Message_Resolver__c`: Optional class type used to "enhance" the event message during the message "relay". See "Runtime Messages Resolution" below.

_NOTE: Messages of the same type should always have the same "Payload". However, "Relay Clients" may process that state in different ways for different subscriptions_

### 2. Define Subscriptions

Each Event may have multiple subscriptions (`TB_Message_Subscription__mdt`). For each subscription, an "Outbox" record will be created to ensure the message is successfully sent. Each subscription has control over how the message is sent.

Properties:

-   `Application__c`: The Application this subscription is a part of
-   `Message_Definition__c`: The message definition to send on
-   `Enabled__c`: Enables/Disables the subscription. NOTE: This only impacts if Outbox records are created or not. Items already in the outbox will continue to be relayed regardless of this flag.
-   `Relay_Client__c`: The class of the client to instantiate. Must implement `TB_IOutboxRelayClient`. The included `TB_GenericHttpRelayClient` will serve the needs of many use cases.
-   `Config__c`: (Optional) JSON string that will be added to the context that is passed into the `TB_IOutboxRelayClient.send` method. Allows a Relay Client to be configured for different subscriptions. See documentation for `TB_GenericHttpRelayClient` for example.
-   `Max_Attempts__c`: Maximum number of times to attempt this message before dead lettering it

### 3. Insert a Message

Construct and insert a `TB_Outbox_Message__c`:

```cs
TB_Outbox_Message__c[] msgs = new TB_Outbox_Message__c[]{};
for(Case c : Trigger.new){
    msgs.add(new TB_Outbox_Message__c(
        Type__c='case_created', // must match a TB_Message_Definition__mdt DeveloperName
        Message__c = c.Id       // whatever you want to send
    ));
}

insert msgs;
```

When a `TB_Outbox_Message__c` is inserted, a `TB_Subscription_Outbox__c` record will be created for each Active subscription related to the message definition.

See the code in `example/main/default` for a full working example.

## Advanced

### Custom TB_IRelayClient

The package comes with a `TB_GenericHttpRelayClient` which can be configured for many simple use cases. However, you may need to write a custom relay client.

_NOTES:_

-   The execution of Relay Clients is not bulkified. The `send` method will be executed once per outbox.
-   The client must not perform DML itself. This will cause the subsequent Relays to fail. **It may fire a Immediate Platform Event**.
-   The same instance is used to send all messages for a given subscription. Keep this in mind if the client is stateful

### Message "enhancement"

Messages can be "Enhanced" during Relay. This allows additional capabilities and behavior.

For example, if you always wanted to pass the most recent data from a record, you could store only the "Record Id" into a `Event.Message__c`. A custom `TB_IOutboxMessageResolver` could then be used to query additional details about the record.

NOTE: A custom `TB_IRelayClient` also has the opportunity to change the message. This should be used when different subscription need different messages. This operation is NOT bulkified!

### Dead-Lettered

A Outbox is "Dead-Lettered" when the "Relay Attempts" exceeds the "Max Attempts" OR the "Manual Dead-Letter" flag has been set.

Once a message has been "Dead-Lettered" relay attempts will stop. To remove a Outboxed Message from the dead letter the `TB_Subscription_Outbox__c` record to:

-   Increase the `Max_Attempts__c` to some value greater than the `Relay_Attempts__c`
-   Uncheck `Manual_Deadletter__c`

### Message Groups

A "Group Identifier" (`Group_Id__c`) can be assigned to a Outbox Message when it is created. For each Application, group messages are guaranteed to be delivered successfully in sequential order. This is useful when you need to ensure temporal consistency of messages.

For example, you might assign all messages related to a group via the record id to ensure messages are delivered in order.

_WARNING: If a message is dead lettered, processing for the Group can not continue until that message is marked as delivered (or deleted)._

### Relay Limits

THe `TB_OutboxRelayQueuable` will attempt to process all the messages in the outbox, without any consideration of if it will exceed the context limits. If a limit is hit, the `TransactionalFinalizer` should result in the Relay Results being properly recorded.

This allows the Relay to operate at maximum efficiency without having to have knowledge of the resources consumed by the different "Relay Clients".

### Record Cleanup

[TODO]: Scheduled job to remove any event where all it's outbox's have completed. Via `TTL` date?
