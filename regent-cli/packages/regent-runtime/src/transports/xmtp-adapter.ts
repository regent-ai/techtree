import type { RegentConfig, XmtpStatus } from "@regent/types";

import { errorMessage, RegentError } from "../errors.js";
import { getXmtpStatus, loadXmtpClientInfo, xmtpMaterialExists } from "../xmtp/manager.js";

export class XmtpAdapter {
  private started = false;
  private lastError: string | null = null;

  constructor(private readonly config: RegentConfig["xmtp"]) {}

  async start(): Promise<void> {
    if (this.started || !this.config.enabled) {
      return;
    }

    if (!xmtpMaterialExists(this.config)) {
      throw new RegentError("xmtp_not_initialized", "XMTP is enabled but not initialized; run `regent xmtp init`");
    }

    try {
      await loadXmtpClientInfo(this.config);
      this.started = true;
      this.lastError = null;
    } catch (error) {
      this.lastError = errorMessage(error);
      throw error;
    }
  }

  async stop(): Promise<void> {
    this.started = false;
  }

  async status(): Promise<XmtpStatus> {
    return getXmtpStatus(this.config, {
      started: this.started,
      lastError: this.lastError,
    });
  }
}
