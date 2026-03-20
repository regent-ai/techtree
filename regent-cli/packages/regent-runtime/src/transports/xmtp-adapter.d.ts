import type { RegentConfig, XmtpStatus } from "@regent/types";
export interface XmtpAdapter {
    start(): Promise<void>;
    stop(): Promise<void>;
    status(): Promise<XmtpStatus>;
}
export declare class ManagedXmtpAdapter implements XmtpAdapter {
    private readonly config;
    private started;
    private lastError;
    private stream;
    private restartTimer;
    private shuttingDown;
    constructor(config: RegentConfig["xmtp"]);
    start(): Promise<void>;
    stop(): Promise<void>;
    status(): Promise<XmtpStatus>;
    private launchStream;
}
