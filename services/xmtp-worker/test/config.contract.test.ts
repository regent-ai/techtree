import { afterEach, describe, it } from "node:test";
import * as assert from "node:assert/strict";
import { loadConfig } from "../src/config.js";

const ORIGINAL_ENV = { ...process.env };

const resetEnv = () => {
  process.env = { ...ORIGINAL_ENV };
};

const withEnv = (vars: Record<string, string | undefined>, run: () => void) => {
  resetEnv();

  for (const [key, value] of Object.entries(vars)) {
    if (value === undefined) {
      delete process.env[key];
    } else {
      process.env[key] = value;
    }
  }

  run();
};

describe("xmtp-worker config contract", () => {
  afterEach(() => {
    resetEnv();
  });

  it("defaults internal endpoints to ensure/ingest/lease/resolve", () => {
    withEnv(
      {
        PHOENIX_INTERNAL_URL: "http://localhost:4100/api/internal",
        XMTP_ROOM_ENSURE_ENDPOINT: undefined,
        XMTP_SHARD_LIST_ENDPOINT: undefined,
        XMTP_MESSAGE_INGEST_ENDPOINT: undefined,
        XMTP_LEASE_MEMBERSHIP_ENDPOINT: undefined,
        XMTP_RESOLVE_MEMBERSHIP_ENDPOINT_TEMPLATE: undefined,
      },
      () => {
        const config = loadConfig();

        assert.equal(
          config.roomEnsureEndpoint,
          "http://localhost:4100/api/internal/xmtp/rooms/ensure",
        );
        assert.equal(
          config.shardListEndpoint,
          "http://localhost:4100/api/internal/xmtp/shards",
        );
        assert.equal(
          config.messageIngestEndpoint,
          "http://localhost:4100/api/internal/xmtp/messages/ingest",
        );
        assert.equal(
          config.leaseMembershipEndpoint,
          "http://localhost:4100/api/internal/xmtp/commands/lease",
        );
        assert.equal(
          config.resolveMembershipEndpointTemplate,
          "http://localhost:4100/api/internal/xmtp/commands/:id/resolve",
        );
      },
    );
  });

  it("honors explicit endpoint overrides", () => {
    withEnv(
      {
        XMTP_ROOM_ENSURE_ENDPOINT: "https://internal.test/rooms/ensure",
        XMTP_SHARD_LIST_ENDPOINT: "https://internal.test/shards",
        XMTP_MESSAGE_INGEST_ENDPOINT: "https://internal.test/messages/ingest",
        XMTP_LEASE_MEMBERSHIP_ENDPOINT: "https://internal.test/commands/lease",
        XMTP_RESOLVE_MEMBERSHIP_ENDPOINT_TEMPLATE:
          "https://internal.test/commands/:id/resolve",
      },
      () => {
        const config = loadConfig();

        assert.equal(config.roomEnsureEndpoint, "https://internal.test/rooms/ensure");
        assert.equal(config.shardListEndpoint, "https://internal.test/shards");
        assert.equal(config.messageIngestEndpoint, "https://internal.test/messages/ingest");
        assert.equal(config.leaseMembershipEndpoint, "https://internal.test/commands/lease");
        assert.equal(
          config.resolveMembershipEndpointTemplate,
          "https://internal.test/commands/:id/resolve",
        );
      },
    );
  });
});
