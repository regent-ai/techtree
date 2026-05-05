import type { HooksOptions } from "phoenix_live_view";

import { LandingPage } from "./hooks/landing-page";
import { HomeChatbox } from "./hooks/home-chatbox";
import { HomeInstallPanel } from "./hooks/home-install-panel";
import { HomeStoryRail } from "./hooks/home-story-rail";
import { registerLazyHooks } from "./hooks/lazy";
import { PublicSiteMotion } from "./hooks/public-site-motion";
import { UnicornHero } from "./hooks/unicorn-hero";

const homeHooks: HooksOptions = {
  LandingPage,
  HomeChatbox,
  HomeInstallPanel,
  HomeStoryRail,
  PublicSiteMotion,
  UnicornHero,
};

registerLazyHooks(homeHooks);
