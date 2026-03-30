import type { HooksOptions } from "phoenix_live_view";

import { HomeIntroModal } from "./hooks/home-intro-modal";
import { HomeTrollbox } from "./hooks/home-trollbox";
import { FrontpageWindows } from "./hooks/home-windows";
import { registerLazyHooks } from "./hooks/lazy";

const homeHooks: HooksOptions = {
  HomeIntroModal,
  FrontpageWindows,
  HomeTrollbox,
};

registerLazyHooks(homeHooks);
