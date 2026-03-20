import { describe, expect, it, vi } from "vitest";

import { RegentRuntime } from "../src/runtime.js";

describe("runtime startup", () => {
  it("rolls back started subsystems when startup fails", async () => {
    const runtime = new RegentRuntime("/tmp/regent-runtime-start.json");
    const gossipsub = {
      start: vi.fn(async () => undefined),
      stop: vi.fn(async () => undefined),
    };
    const xmtp = {
      start: vi.fn(async () => undefined),
      stop: vi.fn(async () => undefined),
    };
    const jsonRpcServer = {
      start: vi.fn(async () => {
        throw new Error("bind failed");
      }),
      stop: vi.fn(async () => undefined),
    };

    Object.assign(runtime as unknown as Record<string, unknown>, {
      gossipsub,
      xmtp,
      jsonRpcServer,
    });

    await expect(runtime.start()).rejects.toThrow("bind failed");
    expect(gossipsub.start).toHaveBeenCalledTimes(1);
    expect(xmtp.start).toHaveBeenCalledTimes(1);
    expect(jsonRpcServer.start).toHaveBeenCalledTimes(1);
    expect(gossipsub.stop).toHaveBeenCalledTimes(1);
    expect(xmtp.stop).toHaveBeenCalledTimes(1);
    expect(runtime.isStarted()).toBe(false);
  });
});
