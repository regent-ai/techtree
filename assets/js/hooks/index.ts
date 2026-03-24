import type { HooksOptions } from "phoenix_live_view";

import { BbhCapsuleWall } from "./bbh-capsule-wall";
import { createLazyHook } from "./lazy";
import { HumanMotion } from "./human-motion";
import { PlatformExplorer } from "./platform-explorer";
import { PlatformScene } from "./platform-scene";

export const platformHooks: HooksOptions = {
  BbhCapsuleWall,
  FrontpageGraph: createLazyHook("FrontpageGraph", "/assets/js/home-graph.js", {
    shouldLoad: ({ el }) => el.dataset.active === "true",
  }),
  FrontpageThingsGrid: createLazyHook("FrontpageThingsGrid", "/assets/js/home.js"),
  HomeIntroModal: createLazyHook("HomeIntroModal", "/assets/js/home.js"),
  FrontpageWindows: createLazyHook("FrontpageWindows", "/assets/js/home.js"),
  HomeTrollbox: createLazyHook("HomeTrollbox", "/assets/js/home.js"),
  HumanMotion,
  PlatformAuth: createLazyHook("PlatformAuth", "/assets/js/platform-auth-entry.js"),
  PlatformExplorer,
  PlatformScene,
};
