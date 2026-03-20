import fs from "node:fs";
import path from "node:path";

import { describe, expect, it } from "vitest";

import { captureOutput } from "../../../test-support/test-helpers.js";
import {
  TEST_WALLET,
  ensureXmtpPolicyFileMock,
  getXmtpStatusMock,
  initializeXmtpMock,
  resolveXmtpInboxIdMock,
  setupCliEntrypointHarness,
} from "./helpers/cli-entrypoint-support.js";

const harness = setupCliEntrypointHarness();

describe("CLI XMTP flows", () => {
  it("initializes XMTP through the local runtime manager", async () => {
    const output = await captureOutput(async () =>
      harness.runCliEntrypoint(["xmtp", "init", "--config", harness.configPath]),
    );

    expect(output.result).toBe(0);
    expect(initializeXmtpMock).toHaveBeenCalledTimes(1);
    expect(JSON.parse(output.stdout)).toMatchObject({
      ok: true,
      enabled: true,
      env: "production",
      client: { inboxId: "owner-inbox" },
    });
  });

  it("prints XMTP local status without going through the daemon", async () => {
    const output = await captureOutput(async () =>
      harness.runCliEntrypoint(["xmtp", "status", "--config", harness.configPath]),
    );

    expect(output.result).toBe(0);
    expect(getXmtpStatusMock).toHaveBeenCalledTimes(1);
    expect(JSON.parse(output.stdout)).toMatchObject({
      enabled: false,
      status: "disabled",
    });
  });

  it("resolves and stores an XMTP owner inbox id", async () => {
    const output = await captureOutput(async () =>
      harness.runCliEntrypoint(["xmtp", "owner", "add", "--address", TEST_WALLET, "--config", harness.configPath]),
    );

    expect(output.result).toBe(0);
    expect(resolveXmtpInboxIdMock).toHaveBeenCalledWith(
      expect.objectContaining({
        dbPath: path.join(harness.tempDir, "xmtp", "production", "client.db"),
      }),
      TEST_WALLET,
    );
    expect(JSON.parse(output.stdout)).toEqual({
      ok: true,
      ownerInboxIds: ["owner-inbox"],
      addedInboxId: "owner-inbox",
    });
    expect(JSON.parse(fs.readFileSync(harness.configPath, "utf8"))).toMatchObject({
      xmtp: { ownerInboxIds: ["owner-inbox"] },
    });
  });

  it("initializes the XMTP public policy file and reports the path", async () => {
    const output = await captureOutput(async () =>
      harness.runCliEntrypoint(["xmtp", "policy", "init", "--config", harness.configPath]),
    );

    expect(output.result).toBe(0);
    expect(ensureXmtpPolicyFileMock).toHaveBeenCalledTimes(1);
    expect(JSON.parse(output.stdout)).toEqual({
      ok: true,
      path: path.join(harness.tempDir, "policies", "xmtp-public.md"),
      created: true,
    });
  });
});
