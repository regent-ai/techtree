import type { SyncLoopOptions } from "./types.js";

export const runSyncLoop = async (options: SyncLoopOptions): Promise<void> => {
  try {
    // Single ingestion mode: async iterable loop only.
    for await (const event of options.stream) {
      if (options.signal.aborted) {
        break;
      }
      await options.onEvent(event);
    }
  } catch (error) {
    await options.onError?.(error);
  }
};
