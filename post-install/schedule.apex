// Schedule the Outbox Relay Cleanup Process
// This ensures that the Outbox Relay processes picks back up if it fails to chain
System.schedule('TB Outbox Relay', '0 0 * * * ?', new TB_ScheduleRelay());

// this cleans up expired outbox records
System.schedule('TB Outbox Cleanup', '0 0 * * * ?', new TB_OutboxCleanup());