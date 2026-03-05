import { loadConfig } from "./config.js";
import {
  completeMembershipCommand as completePhoenixMembershipCommand,
  failMembershipCommand as failPhoenixMembershipCommand,
  leaseMembershipCommand,
} from "./phoenix.js";
import type { MembershipCommand } from "./types.js";

const config = loadConfig();

export const leasePendingMembershipCommand = async (): Promise<MembershipCommand | null> => {
  return leaseMembershipCommand(config.canonicalRoomKey);
};

export const completeMembershipCommand = async (commandId: string): Promise<void> => {
  await completePhoenixMembershipCommand(commandId);
};

export const failMembershipCommand = async (
  commandId: string,
  error: string,
): Promise<void> => {
  await failPhoenixMembershipCommand(commandId, error);
};
