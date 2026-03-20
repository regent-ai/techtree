import type {
  RegentConfig,
  XmtpClientInfo,
  XmtpDmTestResult,
  XmtpGroupAddMembersResult,
  XmtpGroupCreateResult,
  XmtpGroupListResult,
  XmtpInitResult,
  XmtpInstallationRevokeResult,
  XmtpMutationResult,
  XmtpPolicyShowResult,
  XmtpPolicyValidationResult,
  XmtpRecentConversation,
  XmtpRecentError,
  XmtpRuntimeMetrics,
  XmtpStatus,
} from "@regent/types";
import type { ChildProcessByStdio } from "node:child_process";
export interface XmtpRuntimeState {
    connected: boolean;
    metrics: XmtpRuntimeMetrics;
    recentErrors: XmtpRecentError[];
    recentConversations: XmtpRecentConversation[];
}
export declare const xmtpRuntimeStatePath: (config: RegentConfig["xmtp"]) => string;
export declare const readXmtpRuntimeState: (config: RegentConfig["xmtp"]) => XmtpRuntimeState;
export declare const writeXmtpRuntimeState: (config: RegentConfig["xmtp"], state: XmtpRuntimeState) => XmtpRuntimeState;
export declare const updateXmtpRuntimeState: (config: RegentConfig["xmtp"], updater: (current: XmtpRuntimeState) => XmtpRuntimeState) => XmtpRuntimeState;
export declare const recordXmtpRuntimeError: (config: RegentConfig["xmtp"], code: string, message: string) => XmtpRuntimeState;
export declare const recordXmtpRecentConversation: (config: RegentConfig["xmtp"], conversation: XmtpRecentConversation) => XmtpRuntimeState;
export declare const cliConnectionArgs: (config: RegentConfig["xmtp"]) => string[];
export declare const spawnXmtpCliProcess: (config: RegentConfig["xmtp"], args: string[]) => ChildProcessByStdio<null, import("node:stream").Readable, import("node:stream").Readable>;
export declare const ensureXmtpPolicyFile: (config: RegentConfig["xmtp"]) => {
    created: boolean;
    path: string;
};
export declare const showXmtpPolicy: (config: RegentConfig["xmtp"]) => XmtpPolicyShowResult;
export declare const validateXmtpPolicy: (config: RegentConfig["xmtp"]) => XmtpPolicyValidationResult;
export declare const xmtpMaterialExists: (config: RegentConfig["xmtp"]) => boolean;
export declare const loadXmtpClientInfo: (config: RegentConfig["xmtp"]) => Promise<XmtpClientInfo>;
export declare const resolveXmtpInboxId: (config: RegentConfig["xmtp"], identifier: `0x${string}`) => Promise<string | null>;
export declare const resolveXmtpIdentifier: (config: RegentConfig["xmtp"], identifier: string) => Promise<string>;
export declare const ensureXmtpMaterial: (config: RegentConfig["xmtp"]) => Promise<{
    createdWalletKey: boolean;
    createdDbEncryptionKey: boolean;
}>;
export declare const initializeXmtp: (config: RegentConfig["xmtp"], configPath: string) => Promise<XmtpInitResult>;
export declare const listXmtpAllowlist: (config: RegentConfig["xmtp"], list: "owner" | "trusted") => {
    ok: true;
    items: string[];
};
export declare const updateXmtpAllowlist: (current: string[], action: "add" | "remove", inboxId: string) => XmtpMutationResult;
export declare const generateStandaloneXmtpWallet: () => Promise<`0x${string}`>;
export declare const syncXmtpConversations: (config: RegentConfig["xmtp"]) => Promise<void>;
export declare const listXmtpGroups: (config: RegentConfig["xmtp"], options?: {
    sync?: boolean;
}) => Promise<XmtpGroupListResult>;
export declare const createXmtpGroup: (config: RegentConfig["xmtp"], members: string[], options?: {
    name?: string;
    description?: string;
    imageUrl?: string;
    permissions?: "all-members" | "admin-only";
}) => Promise<XmtpGroupCreateResult>;
export declare const addXmtpGroupMembers: (config: RegentConfig["xmtp"], conversationId: string, members: string[]) => Promise<XmtpGroupAddMembersResult>;
export declare const testXmtpDm: (config: RegentConfig["xmtp"], to: `0x${string}`, message: string) => Promise<XmtpDmTestResult>;
export declare const revokeAllOtherXmtpInstallations: (config: RegentConfig["xmtp"]) => Promise<XmtpInstallationRevokeResult>;
export declare const rotateXmtpDbKey: (config: RegentConfig["xmtp"]) => Promise<import("@regent/types").XmtpRotationResult>;
export declare const rotateXmtpWallet: (config: RegentConfig["xmtp"]) => Promise<import("@regent/types").XmtpRotationResult>;
export declare const getXmtpStatus: (config: RegentConfig["xmtp"], options?: {
    started?: boolean;
    lastError?: string | null;
}) => Promise<XmtpStatus>;
export declare const openXmtpPolicyInEditor: (config: RegentConfig["xmtp"]) => {
    opened: boolean;
    editor: string | null;
};
export declare const readXmtpWalletKey: (config: RegentConfig["xmtp"]) => string | null;
