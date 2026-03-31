import type { HooksOptions } from "phoenix_live_view";

import { HomeIntroModal } from "./hooks/home-intro-modal";
import { HomeChatbox } from "./hooks/home-chatbox";
import { registerLazyHooks } from "./hooks/lazy";

const homeHooks: HooksOptions = {
  HomeIntroModal,
  HomeChatbox,
};

registerLazyHooks(homeHooks);
