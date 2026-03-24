import type { HooksOptions } from "phoenix_live_view";

import { FrontpageThingsGrid } from "./hooks/home-grid";
import { HomeIntroModal } from "./hooks/home-intro-modal";
import { HomeTrollbox } from "./hooks/home-trollbox";
import { FrontpageWindows } from "./hooks/home-windows";
import { registerLazyHooks } from "./hooks/lazy";

const homeHooks: HooksOptions = {
  FrontpageThingsGrid,
  HomeIntroModal,
  FrontpageWindows,
  HomeTrollbox,
};

registerLazyHooks(homeHooks);
