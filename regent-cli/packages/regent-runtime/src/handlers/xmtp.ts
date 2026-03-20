import type { XmtpStatus } from "@regent/types";

import type { RuntimeContext } from "../runtime.js";

export async function handleXmtpStatus(ctx: RuntimeContext): Promise<XmtpStatus> {
  return ctx.xmtp.status();
}
