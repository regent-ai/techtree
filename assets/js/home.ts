import type { HooksOptions } from "phoenix_live_view";

import { HomeChatbox } from "./hooks/home-chatbox";
import { HomeInstallPanel } from "./hooks/home-install-panel";
import { HomeStoryRail } from "./hooks/home-story-rail";
import { registerLazyHooks } from "./hooks/lazy";

const homeHooks: HooksOptions = {
  HomeChatbox,
  HomeInstallPanel,
  HomeStoryRail,
};

registerLazyHooks(homeHooks);
