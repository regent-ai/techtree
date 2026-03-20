import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { afterAll, afterEach, beforeAll, beforeEach, vi } from "vitest";

export const TEST_WALLET = "0x1111111111111111111111111111111111111111";
export const TEST_REGISTRY = "0x2222222222222222222222222222222222222222";

const cliMocks = vi.hoisted(() => ({
  daemonCallMock: vi.fn(),
  runDoctorMock: vi.fn(),
  runScopedDoctorMock: vi.fn(),
  runFullDoctorMock: vi.fn(),
  initializeXmtpMock: vi.fn(),
  getXmtpStatusMock: vi.fn(),
  resolveXmtpInboxIdMock: vi.fn(),
  resolveXmtpIdentifierMock: vi.fn(),
  ensureXmtpPolicyFileMock: vi.fn(),
  openXmtpPolicyInEditorMock: vi.fn(),
  testXmtpDmMock: vi.fn(),
  listXmtpGroupsMock: vi.fn(),
  createXmtpGroupMock: vi.fn(),
  addXmtpGroupMembersMock: vi.fn(),
  revokeAllOtherXmtpInstallationsMock: vi.fn(),
  rotateXmtpDbKeyMock: vi.fn(),
  rotateXmtpWalletMock: vi.fn(),
  runTechtreeCoreJsonMock: vi.fn(),
  loadTechtreeV1ClientMock: vi.fn(),
  techtreeV1ClientMock: {
    fetchNode: vi.fn(),
    pinNode: vi.fn(),
    publishNode: vi.fn(),
  },
}));

vi.mock("../../src/daemon-client.js", () => ({
  daemonCall: cliMocks.daemonCallMock,
}));

export const {
  daemonCallMock,
  runDoctorMock,
  runScopedDoctorMock,
  runFullDoctorMock,
  initializeXmtpMock,
  getXmtpStatusMock,
  resolveXmtpInboxIdMock,
  resolveXmtpIdentifierMock,
  ensureXmtpPolicyFileMock,
  openXmtpPolicyInEditorMock,
  testXmtpDmMock,
  listXmtpGroupsMock,
  createXmtpGroupMock,
  addXmtpGroupMembersMock,
  revokeAllOtherXmtpInstallationsMock,
  rotateXmtpDbKeyMock,
  rotateXmtpWalletMock,
  runTechtreeCoreJsonMock,
  loadTechtreeV1ClientMock,
  techtreeV1ClientMock,
} = cliMocks;

export interface CommandCase {
  name: string;
  args: string[];
  expected: unknown;
}

export interface CliEntrypointHarness {
  readonly tempDir: string;
  readonly configPath: string;
  readonly runCliEntrypoint: typeof import("../../src/index.js").runCliEntrypoint;
}

const doctorReport = (mode: "default" | "scoped" | "full", scope?: string) => ({
  ok: true,
  mode,
  ...(scope ? { scope } : {}),
  summary: { ok: 1, warn: 0, fail: 0, skip: 0 },
  checks: [],
  nextSteps: [],
  generatedAt: "2026-03-11T00:00:00.000Z",
});

const defaultDaemonResponse = async (method: string, params?: unknown) => {
  if (method === "xmtp.status") {
    throw new Error("daemon unavailable");
  }

  return params === undefined ? { method } : { method, params };
};

export function setupCliEntrypointHarness(): CliEntrypointHarness {
  let tempDir = "";
  let configPath = "";
  let runCliEntrypoint!: typeof import("../../src/index.js").runCliEntrypoint;

  beforeAll(async () => {
    vi.doMock("@regent/runtime", async () => {
      const actual = await vi.importActual<typeof import("@regent/runtime")>("@regent/runtime");

      return {
        ...actual,
        runDoctor: runDoctorMock,
        runScopedDoctor: runScopedDoctorMock,
        runFullDoctor: runFullDoctorMock,
        initializeXmtp: initializeXmtpMock,
        getXmtpStatus: getXmtpStatusMock,
        resolveXmtpInboxId: resolveXmtpInboxIdMock,
        resolveXmtpIdentifier: resolveXmtpIdentifierMock,
        ensureXmtpPolicyFile: ensureXmtpPolicyFileMock,
        openXmtpPolicyInEditor: openXmtpPolicyInEditorMock,
        testXmtpDm: testXmtpDmMock,
        listXmtpGroups: listXmtpGroupsMock,
        createXmtpGroup: createXmtpGroupMock,
        addXmtpGroupMembers: addXmtpGroupMembersMock,
        revokeAllOtherXmtpInstallations: revokeAllOtherXmtpInstallationsMock,
        rotateXmtpDbKey: rotateXmtpDbKeyMock,
        rotateXmtpWallet: rotateXmtpWalletMock,
        runTechtreeCoreJson: runTechtreeCoreJsonMock,
        loadTechtreeV1Client: loadTechtreeV1ClientMock,
      };
    });

    vi.resetModules();
    ({ runCliEntrypoint } = await import("../../src/index.js"));
  });

  afterAll(() => {
    vi.doUnmock("@regent/runtime");
    vi.resetModules();
  });

  beforeEach(() => {
    tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "regent-cli-dispatch-"));
    configPath = path.join(tempDir, "regent.config.json");

    daemonCallMock.mockReset();
    daemonCallMock.mockImplementation(defaultDaemonResponse);

    runDoctorMock.mockReset();
    runDoctorMock.mockImplementation(async () => doctorReport("default"));

    runScopedDoctorMock.mockReset();
    runScopedDoctorMock.mockImplementation(async (params?: { scope?: string }) =>
      doctorReport("scoped", params?.scope),
    );

    runFullDoctorMock.mockReset();
    runFullDoctorMock.mockImplementation(async () => doctorReport("full"));

    initializeXmtpMock.mockReset();
    initializeXmtpMock.mockImplementation(async (_config, resolvedConfigPath: string) => ({
      configPath: resolvedConfigPath,
      enabled: true,
      env: "production",
      dbPath: path.join(tempDir, "xmtp", "production", "client.db"),
      dbEncryptionKeyPath: path.join(tempDir, "xmtp", "production", "db.key"),
      walletKeyPath: path.join(tempDir, "xmtp", "production", "wallet.key"),
      publicPolicyPath: path.join(tempDir, "policies", "xmtp-public.md"),
      ownerInboxIds: [],
      trustedInboxIds: [],
      profiles: {
        owner: "full",
        public: "messaging",
        group: "messaging",
      },
      createdWalletKey: true,
      createdDbEncryptionKey: true,
      createdPolicyFile: true,
      client: {
        address: TEST_WALLET,
        inboxId: "owner-inbox",
        installationId: "installation-1",
        isRegistered: true,
        appVersion: "xmtp-cli/0.2.0",
        libxmtpVersion: "1.9.1",
      },
    }));

    getXmtpStatusMock.mockReset();
    getXmtpStatusMock.mockImplementation(
      async (xmtpConfig: {
        enabled: boolean;
        env: string;
        dbPath: string;
        walletKeyPath: string;
        dbEncryptionKeyPath: string;
        publicPolicyPath: string;
        ownerInboxIds: string[];
        trustedInboxIds: string[];
        profiles: Record<string, string>;
      }) => ({
        enabled: xmtpConfig.enabled,
        status: xmtpConfig.enabled ? "stopped" : "disabled",
        configured: true,
        connected: false,
        ready: xmtpConfig.enabled,
        started: false,
        env: xmtpConfig.env,
        dbPath: xmtpConfig.dbPath,
        walletKeyPath: xmtpConfig.walletKeyPath,
        dbEncryptionKeyPath: xmtpConfig.dbEncryptionKeyPath,
        publicPolicyPath: xmtpConfig.publicPolicyPath,
        ownerInboxIds: [...xmtpConfig.ownerInboxIds],
        trustedInboxIds: [...xmtpConfig.trustedInboxIds],
        profiles: { ...xmtpConfig.profiles },
        note: "XMTP identity is initialized and ready",
        lastError: null,
        recentErrors: [],
        recentConversations: [],
        metrics: {
          startedAt: null,
          stoppedAt: null,
          lastSyncAt: null,
          lastMessageAt: null,
          receivedMessages: 0,
          sentMessages: 0,
          sendFailures: 0,
          groupsCreated: 0,
          membersAdded: 0,
          installationsRevoked: 0,
          walletRotations: 0,
          dbKeyRotations: 0,
          restarts: 0,
        },
        routeState: xmtpConfig.enabled ? "blocked" : "disabled",
        client: {
          address: TEST_WALLET,
          inboxId: "owner-inbox",
          installationId: "installation-1",
          isRegistered: true,
        },
      }),
    );

    resolveXmtpInboxIdMock.mockReset();
    resolveXmtpInboxIdMock.mockResolvedValue("owner-inbox");
    resolveXmtpIdentifierMock.mockReset();
    resolveXmtpIdentifierMock.mockResolvedValue("owner-inbox");

    ensureXmtpPolicyFileMock.mockReset();
    ensureXmtpPolicyFileMock.mockImplementation((xmtpConfig: { publicPolicyPath: string }) => ({
      created: !fs.existsSync(xmtpConfig.publicPolicyPath),
      path: xmtpConfig.publicPolicyPath,
    }));

    openXmtpPolicyInEditorMock.mockReset();
    openXmtpPolicyInEditorMock.mockReturnValue({
      opened: false,
      editor: null,
    });

    testXmtpDmMock.mockReset();
    testXmtpDmMock.mockResolvedValue({
      ok: true,
      to: TEST_WALLET,
      conversationId: "dm-1",
      messageId: "message-1",
      text: "hello",
    });

    listXmtpGroupsMock.mockReset();
    listXmtpGroupsMock.mockResolvedValue({
      ok: true,
      conversations: [{ id: "group-1", type: "group", name: "Reviewers" }],
    });

    createXmtpGroupMock.mockReset();
    createXmtpGroupMock.mockResolvedValue({
      ok: true,
      id: "group-1",
      name: "Reviewers",
      description: "Team review room",
      imageUrl: null,
      memberCount: 2,
      members: [{ inboxId: "member-1" }, { inboxId: "member-2" }],
    });

    addXmtpGroupMembersMock.mockReset();
    addXmtpGroupMembersMock.mockResolvedValue({
      ok: true,
      conversationId: "group-1",
      addedMembers: ["0x3333333333333333333333333333333333333333"],
      count: 1,
    });

    revokeAllOtherXmtpInstallationsMock.mockReset();
    revokeAllOtherXmtpInstallationsMock.mockResolvedValue({
      ok: true,
      currentInstallationId: "installation-1",
      inboxId: "owner-inbox",
      message: "All other installations have been revoked. Only this installation remains authorized.",
    });

    rotateXmtpDbKeyMock.mockReset();
    rotateXmtpDbKeyMock.mockResolvedValue({
      ok: true,
      kind: "db-key",
      dbPath: path.join(tempDir, "xmtp", "production", "client.db"),
      walletKeyPath: path.join(tempDir, "xmtp", "production", "wallet.key"),
      dbEncryptionKeyPath: path.join(tempDir, "xmtp", "production", "db.key"),
      removedDatabase: true,
    });

    rotateXmtpWalletMock.mockReset();
    rotateXmtpWalletMock.mockResolvedValue({
      ok: true,
      kind: "wallet",
      dbPath: path.join(tempDir, "xmtp", "production", "client.db"),
      walletKeyPath: path.join(tempDir, "xmtp", "production", "wallet.key"),
      dbEncryptionKeyPath: path.join(tempDir, "xmtp", "production", "db.key"),
      removedDatabase: true,
    });

    runTechtreeCoreJsonMock.mockReset();
    runTechtreeCoreJsonMock.mockImplementation(async (entrypoint: string, input?: unknown) => {
      if (entrypoint.endsWith(".compile")) {
        const workspacePath =
          typeof input === "object" && input && "workspace_path" in input
            ? String((input as { workspace_path?: unknown }).workspace_path ?? tempDir)
            : tempDir;
        const distPath = path.join(workspacePath, "dist");

        return {
          ok: true,
          entrypoint,
          input,
          workspace_path: workspacePath,
          dist_path: distPath,
          manifest_path: path.join(distPath, `${entrypoint.split(".")[0]}.manifest.json`),
          payload_index_path: path.join(distPath, "payload.index.json"),
          node_header_path: path.join(distPath, "node-header.json"),
          checksums_path: path.join(distPath, "checksums.txt"),
          node_id: `0x${entrypoint.replace(".", "").padEnd(64, "0").slice(0, 64)}`,
          manifest_hash: `sha256:${"11".repeat(32)}`,
          payload_hash: `sha256:${"22".repeat(32)}`,
          node_header: {
            id: `0x${entrypoint.replace(".", "").padEnd(64, "0").slice(0, 64)}`,
            subjectId: `0x${"33".repeat(32)}`,
            auxId: `0x${"44".repeat(32)}`,
            payloadHash: `sha256:${"22".repeat(32)}`,
            nodeType: entrypoint.startsWith("artifact") ? 1 : entrypoint.startsWith("run") ? 2 : 3,
            schemaVersion: 1,
            flags: 0,
            author: TEST_WALLET,
          },
          payload_index: {
            schema_version: "techtree.payload-index.v1",
            node_type: entrypoint.startsWith("artifact")
              ? "artifact"
              : entrypoint.startsWith("run")
                ? "run"
                : "review",
            files: [],
            external_blobs: [],
          },
        };
      }

      return {
        ok: true,
        entrypoint,
        input,
      };
    });

    loadTechtreeV1ClientMock.mockReset();
    loadTechtreeV1ClientMock.mockReturnValue(techtreeV1ClientMock);

    techtreeV1ClientMock.fetchNode.mockReset();
    techtreeV1ClientMock.fetchNode.mockImplementation(async (input: { node_id: string }) => ({
      ok: true,
      node_id: input.node_id,
      node_type: "artifact",
      manifest_cid: "bafy-fetch-manifest",
      payload_cid: "bafy-fetch-payload",
      verified: true,
    }));
    techtreeV1ClientMock.pinNode.mockReset();
    techtreeV1ClientMock.pinNode.mockImplementation(async (input: { node_type: string }) => ({
      ok: true,
      node_id: `0x${input.node_type.padEnd(64, "0")}` as `0x${string}`,
      manifest_cid: `bafy-${input.node_type}-manifest`,
      payload_cid: `bafy-${input.node_type}-payload`,
    }));
    techtreeV1ClientMock.publishNode.mockReset();
    techtreeV1ClientMock.publishNode.mockImplementation(
      async (input: { node_type: string; manifest_cid: string; payload_cid: string }) => ({
        ok: true,
        node_id: `0x${input.node_type.padEnd(64, "0")}` as `0x${string}`,
        manifest_cid: input.manifest_cid,
        payload_cid: input.payload_cid,
        tx_hash: `0x${"ab".repeat(32)}` as `0x${string}`,
      }),
    );
  });

  afterEach(() => {
    daemonCallMock.mockClear();
    runDoctorMock.mockClear();
    runScopedDoctorMock.mockClear();
    runFullDoctorMock.mockClear();
    initializeXmtpMock.mockClear();
    getXmtpStatusMock.mockClear();
    resolveXmtpInboxIdMock.mockClear();
    resolveXmtpIdentifierMock.mockClear();
    ensureXmtpPolicyFileMock.mockClear();
    openXmtpPolicyInEditorMock.mockClear();
    testXmtpDmMock.mockClear();
    listXmtpGroupsMock.mockClear();
    createXmtpGroupMock.mockClear();
    addXmtpGroupMembersMock.mockClear();
    revokeAllOtherXmtpInstallationsMock.mockClear();
    rotateXmtpDbKeyMock.mockClear();
    rotateXmtpWalletMock.mockClear();
    runTechtreeCoreJsonMock.mockClear();
    loadTechtreeV1ClientMock.mockClear();
    techtreeV1ClientMock.fetchNode.mockClear();
    techtreeV1ClientMock.pinNode.mockClear();
    techtreeV1ClientMock.publishNode.mockClear();
  });

  return {
    get tempDir() {
      return tempDir;
    },
    get configPath() {
      return configPath;
    },
    get runCliEntrypoint() {
      return runCliEntrypoint;
    },
  };
}
