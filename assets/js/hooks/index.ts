import type { HooksOptions } from "phoenix_live_view";

import { hooks as regentHooks } from "../../../../design-system/regent_ui/assets/js/regent";
import { BbhCapsuleWall } from "./bbh-capsule-wall";
import { createLazyHook } from "./lazy";
import { HumanMotion } from "./human-motion";
import { PlatformExplorer } from "./platform-explorer";
import { PlatformScene } from "./platform-scene";

export const platformHooks: HooksOptions = {
  ...regentHooks,
  BbhCapsuleWall,
  LandingPage: createLazyHook("LandingPage", "/assets/js/home.js"),
  HomeChatbox: createLazyHook("HomeChatbox", "/assets/js/home.js"),
  HomeInstallPanel: createLazyHook("HomeInstallPanel", "/assets/js/home.js"),
  HomeStoryRail: createLazyHook("HomeStoryRail", "/assets/js/home.js"),
  PublicSiteMotion: createLazyHook("PublicSiteMotion", "/assets/js/home.js"),
  UnicornHero: createLazyHook("UnicornHero", "/assets/js/home.js"),
  HumanMotion,
  PlatformAuth: createLazyHook("PlatformAuth", "/assets/js/platform-auth-entry.js"),
  PlatformExplorer,
  PlatformScene,
};
