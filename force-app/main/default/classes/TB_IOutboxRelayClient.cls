public interface TB_IOutboxRelayClient {
    /**
     * Must throw exception on failure
     */
    void send(TB_OutboxRelayContext ctx);
}