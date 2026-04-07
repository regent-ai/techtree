import type { HooksOptions } from "phoenix_live_view";

import { HomeChatbox } from "./hooks/home-chatbox";
import { HomeInstallPanel } from "./hooks/home-install-panel";
import { registerLazyHooks } from "./hooks/lazy";

const homeHooks: HooksOptions = {
  HomeChatbox,
  HomeInstallPanel,
};

registerLazyHooks(homeHooks);
