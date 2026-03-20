import type { HooksOptions } from "phoenix_live_view";

import { createLazyHook } from "./lazy";
import { HumanMotion } from "./human-motion";
import { PlatformCreator } from "./platform-creator";
import { PlatformExplorer } from "./platform-explorer";
import { PlatformScene } from "./platform-scene";

export const platformHooks: HooksOptions = {
  FrontpageGraph: createLazyHook("FrontpageGraph", "/assets/js/home-graph.js", {
    shouldLoad: ({ el }) => el.dataset.active === "true",
  }),
  FrontpageThingsGrid: createLazyHook("FrontpageThingsGrid", "/assets/js/home.js"),
  FrontpageWindows: createLazyHook("FrontpageWindows", "/assets/js/home.js"),
  HomeTrollbox: createLazyHook("HomeTrollbox", "/assets/js/home.js"),
  HumanMotion,
  PlatformAuth: createLazyHook("PlatformAuth", "/assets/js/platform-auth-entry.js"),
  PlatformCreator,
  PlatformExplorer,
  PlatformScene,
};
