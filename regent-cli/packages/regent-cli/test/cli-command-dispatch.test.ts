import fs from "node:fs";
import path from "node:path";

import { describe, expect, it } from "vitest";

import { captureOutput } from "../../../test-support/test-helpers.js";
import {
  CommandCase,
  TEST_REGISTRY,
  TEST_WALLET,
  daemonCallMock,
  runDoctorMock,
  runFullDoctorMock,
  runScopedDoctorMock,
  setupCliEntrypointHarness,
} from "./helpers/cli-entrypoint-support.js";

const harness = setupCliEntrypointHarness();

const commandCases: CommandCase[] = [
  {
    name: "auth siwa login",
    args: [
      "auth",
      "siwa",
      "login",
      "--wallet-address",
      TEST_WALLET,
      "--chain-id",
      "11155111",
      "--registry-address",
      TEST_REGISTRY,
      "--token-id",
      "99",
      "--audience",
      "techtree",
    ],
    expected: {
      method: "auth.siwa.login",
      params: {
        walletAddress: TEST_WALLET,
        chainId: 11155111,
        registryAddress: TEST_REGISTRY,
        tokenId: "99",
        audience: "techtree",
      },
    },
  },
  { name: "auth siwa status", args: ["auth", "siwa", "status"], expected: { method: "auth.siwa.status" } },
  { name: "auth siwa logout", args: ["auth", "siwa", "logout"], expected: { method: "auth.siwa.logout" } },
  { name: "techtree status", args: ["techtree", "status"], expected: { method: "techtree.status" } },
  {
    name: "techtree nodes list",
    args: ["techtree", "nodes", "list", "--limit", "5", "--seed", "ml"],
    expected: { method: "techtree.nodes.list", params: { limit: 5, seed: "ml" } },
  },
  { name: "techtree node get", args: ["techtree", "node", "get", "42"], expected: { method: "techtree.nodes.get", params: { id: 42 } } },
  {
    name: "techtree node children",
    args: ["techtree", "node", "children", "42", "--limit", "3"],
    expected: { method: "techtree.nodes.children", params: { id: 42, limit: 3 } },
  },
  {
    name: "techtree node comments",
    args: ["techtree", "node", "comments", "42", "--limit", "4"],
    expected: { method: "techtree.nodes.comments", params: { id: 42, limit: 4 } },
  },
  {
    name: "techtree activity",
    args: ["techtree", "activity", "--limit", "4"],
    expected: { method: "techtree.activity.list", params: { limit: 4 } },
  },
  {
    name: "techtree search",
    args: ["techtree", "search", "--query", "root", "--limit", "2"],
    expected: { method: "techtree.search.query", params: { q: "root", limit: 2 } },
  },
  {
    name: "techtree node work-packet",
    args: ["techtree", "node", "work-packet", "42"],
    expected: { method: "techtree.nodes.workPacket", params: { id: 42 } },
  },
  { name: "techtree watch list", args: ["techtree", "watch", "list"], expected: { method: "techtree.watch.list" } },
  {
    name: "techtree watch",
    args: ["techtree", "watch", "42"],
    expected: { method: "techtree.watch.create", params: { nodeId: 42 } },
  },
  {
    name: "techtree unwatch",
    args: ["techtree", "unwatch", "42"],
    expected: { method: "techtree.watch.delete", params: { nodeId: 42 } },
  },
  {
    name: "techtree star",
    args: ["techtree", "star", "42"],
    expected: { method: "techtree.stars.create", params: { nodeId: 42 } },
  },
  {
    name: "techtree unstar",
    args: ["techtree", "unstar", "42"],
    expected: { method: "techtree.stars.delete", params: { nodeId: 42 } },
  },
  {
    name: "techtree inbox",
    args: ["techtree", "inbox", "--cursor", "10", "--limit", "20", "--seed", "ml", "--kind", "comment,mention"],
    expected: { method: "techtree.inbox.get", params: { cursor: 10, limit: 20, seed: "ml", kind: ["comment", "mention"] } },
  },
  {
    name: "techtree opportunities",
    args: ["techtree", "opportunities", "--limit", "6", "--seed", "ml", "--kind", "review,build"],
    expected: { method: "techtree.opportunities.list", params: { limit: 6, seed: "ml", kind: ["review", "build"] } },
  },
  { name: "gossipsub status", args: ["gossipsub", "status"], expected: { method: "gossipsub.status" } },
];

describe("CLI command dispatch", () => {
  for (const testCase of commandCases) {
    it(`dispatches ${testCase.name}`, async () => {
      const output = await captureOutput(async () =>
        harness.runCliEntrypoint([...testCase.args, "--config", harness.configPath]),
      );

      expect(output.result).toBe(0);
      expect(output.stderr).toBe("");
      expect(JSON.parse(output.stdout)).toEqual(testCase.expected);
    });
  }

  it("dispatches doctor default through the local runtime doctor engine", async () => {
    const output = await captureOutput(async () =>
      harness.runCliEntrypoint(["doctor", "--json", "--config", harness.configPath]),
    );

    expect(output.result).toBe(0);
    expect(output.stderr).toBe("");
    expect(daemonCallMock).not.toHaveBeenCalled();
    expect(runDoctorMock).toHaveBeenCalledWith(
      { json: true, verbose: false, fix: false },
      { configPath: harness.configPath },
    );
  });

  it("passes modern doctor output flags through the local runtime doctor engine", async () => {
    const output = await captureOutput(async () =>
      harness.runCliEntrypoint(["doctor", "--quiet", "--only-failures", "--ci", "--config", harness.configPath]),
    );

    expect(output.result).toBe(0);
    expect(output.stderr).toBe("");
    expect(runDoctorMock).toHaveBeenCalledWith(
      { json: false, verbose: false, fix: false },
      { configPath: harness.configPath },
    );
  });

  it("dispatches doctor scoped through the local runtime doctor engine", async () => {
    const output = await captureOutput(async () =>
      harness.runCliEntrypoint(["doctor", "auth", "--json", "--verbose", "--fix", "--config", harness.configPath]),
    );

    expect(output.result).toBe(0);
    expect(output.stderr).toBe("");
    expect(daemonCallMock).not.toHaveBeenCalled();
    expect(runScopedDoctorMock).toHaveBeenCalledWith(
      { scope: "auth", json: true, verbose: true, fix: true },
      { configPath: harness.configPath },
    );
  });

  it("dispatches doctor full through the local runtime doctor engine", async () => {
    const output = await captureOutput(async () =>
      harness.runCliEntrypoint(["doctor", "--json", "--full", "--known-parent-id", "7", "--config", harness.configPath]),
    );

    expect(output.result).toBe(0);
    expect(output.stderr).toBe("");
    expect(daemonCallMock).not.toHaveBeenCalled();
    expect(runFullDoctorMock).toHaveBeenCalledWith(
      { json: true, verbose: false, fix: false, knownParentId: 7, cleanupCommentBodyPrefix: undefined },
      { configPath: harness.configPath },
    );
  });

  it("creates a node payload from notebook and skill inputs", async () => {
    const notebookPath = path.join(harness.tempDir, "notebook.py");
    const skillPath = path.join(harness.tempDir, "skill.md");
    fs.writeFileSync(notebookPath, "print('hello')\n", "utf8");
    fs.writeFileSync(skillPath, "# Skill\n", "utf8");

    const output = await captureOutput(async () =>
      harness.runCliEntrypoint([
        "techtree",
        "node",
        "create",
        "--config",
        harness.configPath,
        "--seed",
        "ml",
        "--kind",
        "hypothesis",
        "--title",
        "Example node",
        "--parent-id",
        "1",
        "--notebook-source",
        `@${notebookPath}`,
        "--slug",
        "example-node",
        "--summary",
        "Node summary",
        "--skill-slug",
        "test-skill",
        "--skill-version",
        "1.0.0",
        "--skill-md",
        `@${skillPath}`,
        "--idempotency-key",
        "node-key-1",
      ]),
    );

    expect(output.result).toBe(0);
    expect(JSON.parse(output.stdout)).toEqual({
      method: "techtree.nodes.create",
      params: {
        seed: "ml",
        kind: "hypothesis",
        title: "Example node",
        parent_id: 1,
        notebook_source: "print('hello')\n",
        slug: "example-node",
        summary: "Node summary",
        skill_slug: "test-skill",
        skill_version: "1.0.0",
        skill_md_body: "# Skill\n",
        idempotency_key: "node-key-1",
      },
    });
  });

  it("creates a node payload with repeated sidelinks", async () => {
    const notebookPath = path.join(harness.tempDir, "notebook-sidelinks.py");
    fs.writeFileSync(notebookPath, "print('hello with sidelinks')\n", "utf8");

    const output = await captureOutput(async () =>
      harness.runCliEntrypoint([
        "techtree",
        "node",
        "create",
        "--config",
        harness.configPath,
        "--seed",
        "ml",
        "--kind",
        "hypothesis",
        "--title",
        "Example node with sidelinks",
        "--parent-id",
        "1",
        "--notebook-source",
        `@${notebookPath}`,
        "--sidelink",
        "2:related:3",
        "--sidelink=5:supports",
      ]),
    );

    expect(output.result).toBe(0);
    expect(JSON.parse(output.stdout)).toEqual({
      method: "techtree.nodes.create",
      params: {
        seed: "ml",
        kind: "hypothesis",
        title: "Example node with sidelinks",
        parent_id: 1,
        notebook_source: "print('hello with sidelinks')\n",
        sidelinks: [
          { node_id: 2, tag: "related", ordinal: 3 },
          { node_id: 5, tag: "supports" },
        ],
      },
    });
  });

  it("creates a comment payload", async () => {
    const output = await captureOutput(async () =>
      harness.runCliEntrypoint([
        "techtree",
        "comment",
        "add",
        "--config",
        harness.configPath,
        "--node-id",
        "9",
        "--body-markdown",
        "hello world",
        "--body-plaintext",
        "hello world",
        "--idempotency-key",
        "comment-key-1",
      ]),
    );

    expect(output.result).toBe(0);
    expect(JSON.parse(output.stdout)).toEqual({
      method: "techtree.comments.create",
      params: {
        node_id: 9,
        body_markdown: "hello world",
        body_plaintext: "hello world",
        idempotency_key: "comment-key-1",
      },
    });
  });

  it("returns JSON errors for invalid node ids", async () => {
    const output = await captureOutput(async () =>
      harness.runCliEntrypoint(["techtree", "node", "get", "0", "--config", harness.configPath]),
    );

    expect(output.result).toBe(1);
    expect(output.stdout).toBe("");
    expect(JSON.parse(output.stderr)).toEqual({ error: { message: "invalid node id" } });
  });

  it("returns JSON errors for partial skill triplets", async () => {
    const notebookPath = path.join(harness.tempDir, "partial-notebook.py");
    fs.writeFileSync(notebookPath, "print('partial')\n", "utf8");

    const output = await captureOutput(async () =>
      harness.runCliEntrypoint([
        "techtree",
        "node",
        "create",
        "--config",
        harness.configPath,
        "--seed",
        "ml",
        "--kind",
        "hypothesis",
        "--title",
        "Bad node",
        "--notebook-source",
        `@${notebookPath}`,
        "--skill-slug",
        "test-skill",
      ]),
    );

    expect(output.result).toBe(1);
    expect(JSON.parse(output.stderr)).toEqual({
      error: {
        message: "skill node inputs must include --skill-slug, --skill-version, and --skill-md together",
      },
    });
  });

  it("returns JSON errors when techtree search is missing --query", async () => {
    const output = await captureOutput(async () =>
      harness.runCliEntrypoint(["techtree", "search", "--config", harness.configPath]),
    );

    expect(output.result).toBe(1);
    expect(JSON.parse(output.stderr)).toEqual({
      error: {
        message: "missing required argument: --query",
      },
    });
  });

  it("returns daemon errors as JSON", async () => {
    const { JsonRpcError } = await import("@regent/runtime");
    daemonCallMock.mockRejectedValueOnce(new JsonRpcError("daemon exploded", { code: "daemon_exploded" }));

    const output = await captureOutput(async () =>
      harness.runCliEntrypoint(["auth", "siwa", "login", "--config", harness.configPath]),
    );

    expect(output.result).toBe(1);
    expect(JSON.parse(output.stderr)).toEqual({
      error: { code: "daemon_exploded", message: "daemon exploded" },
    });
  });

  it("returns exit code 3 when doctor surfaces an internal runtime failure", async () => {
    runDoctorMock.mockResolvedValueOnce({
      ok: false,
      mode: "default",
      summary: { ok: 0, warn: 0, fail: 1, skip: 0 },
      checks: [
        {
          id: "runtime.internal",
          scope: "runtime",
          status: "fail",
          title: "internal check",
          message: "Doctor check crashed before it could return a result",
          details: { internal: true, code: "doctor_check_crashed" },
          startedAt: "2026-03-11T00:00:00.000Z",
          finishedAt: "2026-03-11T00:00:00.001Z",
          durationMs: 1,
        },
      ],
      nextSteps: ["Inspect the failing doctor check implementation and retry"],
      generatedAt: "2026-03-11T00:00:00.002Z",
    });

    const output = await captureOutput(async () =>
      harness.runCliEntrypoint(["doctor", "--json", "--config", harness.configPath]),
    );

    expect(output.result).toBe(3);
    expect(output.stderr).toBe("");
  });

  it("treats flags without values as missing required inputs instead of swallowing the next flag", async () => {
    const output = await captureOutput(async () =>
      harness.runCliEntrypoint([
        "techtree",
        "node",
        "create",
        "--config",
        harness.configPath,
        "--seed",
        "--kind",
        "hypothesis",
        "--title",
        "Bad node",
        "--notebook-source",
        "print('oops')",
      ]),
    );

    expect(output.result).toBe(1);
    expect(JSON.parse(output.stderr)).toEqual({
      error: {
        message: "missing required argument: --seed",
      },
    });
  });
});
