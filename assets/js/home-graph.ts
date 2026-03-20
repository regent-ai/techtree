import type { HooksOptions } from "phoenix_live_view";

import { FrontpageGraph } from "./hooks/home-graph";
import { registerLazyHooks } from "./hooks/lazy";

const homeGraphHooks: HooksOptions = {
  FrontpageGraph,
};

registerLazyHooks(homeGraphHooks);
