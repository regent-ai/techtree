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
  ensureXmtpPolicyFileMock: vi.fn(),
  openXmtpPolicyInEditorMock: vi.fn(),
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
  ensureXmtpPolicyFileMock,
  openXmtpPolicyInEditorMock,
} = cliMocks;

export interface CommandCase {
  name: string;
  args: string[];
  expected: Record<string, unknown>;
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

const defaultDaemonResponse = async (method: string, params?: unknown) =>
  params === undefined ? { method } : { method, params };

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
        ensureXmtpPolicyFile: ensureXmtpPolicyFileMock,
        openXmtpPolicyInEditor: openXmtpPolicyInEditorMock,
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
  });

  afterEach(() => {
    daemonCallMock.mockClear();
    runDoctorMock.mockClear();
    runScopedDoctorMock.mockClear();
    runFullDoctorMock.mockClear();
    initializeXmtpMock.mockClear();
    getXmtpStatusMock.mockClear();
    resolveXmtpInboxIdMock.mockClear();
    ensureXmtpPolicyFileMock.mockClear();
    openXmtpPolicyInEditorMock.mockClear();
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
