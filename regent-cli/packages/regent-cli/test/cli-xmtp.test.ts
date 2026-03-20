import fs from "node:fs";
import path from "node:path";

import { describe, expect, it } from "vitest";

import { captureOutput } from "../../../test-support/test-helpers.js";
import {
  TEST_WALLET,
  addXmtpGroupMembersMock,
  createXmtpGroupMock,
  ensureXmtpPolicyFileMock,
  getXmtpStatusMock,
  initializeXmtpMock,
  listXmtpGroupsMock,
  resolveXmtpIdentifierMock,
  revokeAllOtherXmtpInstallationsMock,
  rotateXmtpDbKeyMock,
  rotateXmtpWalletMock,
  runScopedDoctorMock,
  setupCliEntrypointHarness,
  testXmtpDmMock,
} from "./helpers/cli-entrypoint-support.js";

const harness = setupCliEntrypointHarness();

describe("CLI XMTP flows", () => {
  it("initializes XMTP, enables it in config, and accepts a one-shot owner", async () => {
    const output = await captureOutput(async () =>
      harness.runCliEntrypoint(["xmtp", "init", "--owner", TEST_WALLET, "--config", harness.configPath]),
    );

    expect(output.result).toBe(0);
    expect(initializeXmtpMock).toHaveBeenCalledTimes(1);
    expect(resolveXmtpIdentifierMock).toHaveBeenCalledWith(
      expect.objectContaining({
        dbPath: path.join(harness.tempDir, "xmtp", "production", "client.db"),
      }),
      TEST_WALLET,
    );
    expect(JSON.parse(output.stdout)).toMatchObject({
      ok: true,
      enabled: true,
      env: "production",
      ownerInboxIds: ["owner-inbox"],
      client: { inboxId: "owner-inbox" },
    });
    expect(JSON.parse(fs.readFileSync(harness.configPath, "utf8"))).toMatchObject({
      xmtp: {
        enabled: true,
        ownerInboxIds: ["owner-inbox"],
      },
    });
  });

  it("prints XMTP local status when the daemon is unavailable", async () => {
    const output = await captureOutput(async () =>
      harness.runCliEntrypoint(["xmtp", "status", "--config", harness.configPath]),
    );

    expect(output.result).toBe(0);
    expect(getXmtpStatusMock).toHaveBeenCalledTimes(1);
    expect(JSON.parse(output.stdout)).toMatchObject({
      enabled: false,
      status: "disabled",
      recentErrors: [],
      metrics: { receivedMessages: 0 },
    });
  });

  it("stores, lists, and removes owner inbox ids", async () => {
    await captureOutput(async () =>
      harness.runCliEntrypoint(["xmtp", "owner", "add", "--address", TEST_WALLET, "--config", harness.configPath]),
    );

    const listed = await captureOutput(async () =>
      harness.runCliEntrypoint(["xmtp", "owner", "list", "--config", harness.configPath]),
    );
    expect(JSON.parse(listed.stdout)).toEqual({
      ok: true,
      items: ["owner-inbox"],
    });

    const removed = await captureOutput(async () =>
      harness.runCliEntrypoint(["xmtp", "owner", "remove", "--address", TEST_WALLET, "--config", harness.configPath]),
    );
    expect(JSON.parse(removed.stdout)).toEqual({
      ok: true,
      updated: [],
      changedInboxId: "owner-inbox",
    });
  });

  it("stores, lists, and removes trusted inbox ids", async () => {
    const added = await captureOutput(async () =>
      harness.runCliEntrypoint(["xmtp", "trusted", "add", "--address", TEST_WALLET, "--config", harness.configPath]),
    );

    expect(JSON.parse(added.stdout)).toEqual({
      ok: true,
      updated: ["owner-inbox"],
      changedInboxId: "owner-inbox",
    });

    const listed = await captureOutput(async () =>
      harness.runCliEntrypoint(["xmtp", "trusted", "list", "--config", harness.configPath]),
    );
    expect(JSON.parse(listed.stdout)).toEqual({
      ok: true,
      items: ["owner-inbox"],
    });

    const removed = await captureOutput(async () =>
      harness.runCliEntrypoint(["xmtp", "trusted", "remove", "--address", TEST_WALLET, "--config", harness.configPath]),
    );
    expect(JSON.parse(removed.stdout)).toEqual({
      ok: true,
      updated: [],
      changedInboxId: "owner-inbox",
    });
  });

  it("initializes, shows, and validates the XMTP public policy file", async () => {
    const initialized = await captureOutput(async () =>
      harness.runCliEntrypoint(["xmtp", "policy", "init", "--config", harness.configPath]),
    );

    expect(initialized.result).toBe(0);
    expect(ensureXmtpPolicyFileMock).toHaveBeenCalledTimes(1);
    expect(JSON.parse(initialized.stdout)).toEqual({
      ok: true,
      path: path.join(harness.tempDir, "policies", "xmtp-public.md"),
      created: true,
    });

    fs.mkdirSync(path.join(harness.tempDir, "policies"), { recursive: true });
    fs.writeFileSync(path.join(harness.tempDir, "policies", "xmtp-public.md"), "Public messages stay restricted.\n");

    const shown = await captureOutput(async () =>
      harness.runCliEntrypoint(["xmtp", "policy", "show", "--config", harness.configPath]),
    );
    expect(JSON.parse(shown.stdout)).toEqual({
      ok: true,
      path: path.join(harness.tempDir, "policies", "xmtp-public.md"),
      content: "Public messages stay restricted.\n",
    });

    const validated = await captureOutput(async () =>
      harness.runCliEntrypoint(["xmtp", "policy", "validate", "--config", harness.configPath]),
    );
    expect(validated.result).toBe(1);
    expect(JSON.parse(validated.stdout)).toEqual({
      ok: false,
      path: path.join(harness.tempDir, "policies", "xmtp-public.md"),
      issues: ["Policy file is too short to constrain public messaging safely."],
    });
  });

  it("runs a controlled XMTP DM test", async () => {
    const output = await captureOutput(async () =>
      harness.runCliEntrypoint([
        "xmtp",
        "test",
        "dm",
        "--to",
        TEST_WALLET,
        "--message",
        "hello",
        "--config",
        harness.configPath,
      ]),
    );

    expect(output.result).toBe(0);
    expect(testXmtpDmMock).toHaveBeenCalledWith(
      expect.objectContaining({
        dbPath: path.join(harness.tempDir, "xmtp", "production", "client.db"),
      }),
      TEST_WALLET,
      "hello",
    );
    expect(JSON.parse(output.stdout)).toEqual({
      ok: true,
      to: TEST_WALLET,
      conversationId: "dm-1",
      messageId: "message-1",
      text: "hello",
    });
  });

  it("creates, adds members to, and lists XMTP groups", async () => {
    const created = await captureOutput(async () =>
      harness.runCliEntrypoint([
        "xmtp",
        "group",
        "create",
        "0x3333333333333333333333333333333333333333",
        "0x4444444444444444444444444444444444444444",
        "--name",
        "Reviewers",
        "--description",
        "Team review room",
        "--config",
        harness.configPath,
      ]),
    );

    expect(created.result).toBe(0);
    expect(createXmtpGroupMock).toHaveBeenCalledWith(
      expect.objectContaining({
        dbPath: path.join(harness.tempDir, "xmtp", "production", "client.db"),
      }),
      [
        "0x3333333333333333333333333333333333333333",
        "0x4444444444444444444444444444444444444444",
      ],
      {
        name: "Reviewers",
        description: "Team review room",
        imageUrl: undefined,
        permissions: undefined,
      },
    );

    const added = await captureOutput(async () =>
      harness.runCliEntrypoint([
        "xmtp",
        "group",
        "add-member",
        "group-1",
        "0x3333333333333333333333333333333333333333",
        "--config",
        harness.configPath,
      ]),
    );

    expect(added.result).toBe(0);
    expect(addXmtpGroupMembersMock).toHaveBeenCalledWith(
      expect.objectContaining({
        dbPath: path.join(harness.tempDir, "xmtp", "production", "client.db"),
      }),
      "group-1",
      ["0x3333333333333333333333333333333333333333"],
    );

    const listed = await captureOutput(async () =>
      harness.runCliEntrypoint(["xmtp", "group", "list", "--sync", "--config", harness.configPath]),
    );
    expect(listXmtpGroupsMock).toHaveBeenCalledWith(
      expect.objectContaining({
        dbPath: path.join(harness.tempDir, "xmtp", "production", "client.db"),
      }),
      { sync: true },
    );
    expect(JSON.parse(listed.stdout)).toEqual({
      ok: true,
      conversations: [{ id: "group-1", type: "group", name: "Reviewers" }],
    });
  });

  it("runs XMTP installation hygiene commands", async () => {
    const revoked = await captureOutput(async () =>
      harness.runCliEntrypoint(["xmtp", "revoke-other-installations", "--config", harness.configPath]),
    );
    expect(revoked.result).toBe(0);
    expect(revokeAllOtherXmtpInstallationsMock).toHaveBeenCalledTimes(1);

    const rotatedDb = await captureOutput(async () =>
      harness.runCliEntrypoint(["xmtp", "rotate-db-key", "--config", harness.configPath]),
    );
    expect(rotatedDb.result).toBe(0);
    expect(rotateXmtpDbKeyMock).toHaveBeenCalledTimes(1);

    const rotatedWallet = await captureOutput(async () =>
      harness.runCliEntrypoint(["xmtp", "rotate-wallet", "--config", harness.configPath]),
    );
    expect(rotatedWallet.result).toBe(0);
    expect(rotateXmtpWalletMock).toHaveBeenCalledTimes(1);
  });

  it("dispatches xmtp doctor to the XMTP-only scope", async () => {
    const output = await captureOutput(async () =>
      harness.runCliEntrypoint(["xmtp", "doctor", "--json", "--config", harness.configPath]),
    );

    expect(output.result).toBe(0);
    expect(runScopedDoctorMock).toHaveBeenCalledWith(
      { scope: "xmtp", json: true, verbose: false, fix: false },
      { configPath: harness.configPath },
    );
  });
});
