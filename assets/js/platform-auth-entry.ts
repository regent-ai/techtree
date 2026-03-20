import type { HooksOptions } from "phoenix_live_view";

import { PlatformAuth } from "./hooks/platform-auth";
import { registerLazyHooks } from "./hooks/lazy";

const platformAuthHooks: HooksOptions = {
  PlatformAuth,
};

registerLazyHooks(platformAuthHooks);
