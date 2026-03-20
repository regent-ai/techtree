import type { RegentRpcMethod } from "@regent/types";

export const REGENT_RPC_METHODS = {
  runtimePing: "runtime.ping",
  runtimeStatus: "runtime.status",
  runtimeShutdown: "runtime.shutdown",
  doctorRun: "doctor.run",
  doctorRunScoped: "doctor.runScoped",
  doctorRunFull: "doctor.runFull",
  authSiwaLogin: "auth.siwa.login",
  authSiwaLogout: "auth.siwa.logout",
  authSiwaStatus: "auth.siwa.status",
  techtreeStatus: "techtree.status",
  techtreeNodesList: "techtree.nodes.list",
  techtreeNodesGet: "techtree.nodes.get",
  techtreeNodesChildren: "techtree.nodes.children",
  techtreeNodesComments: "techtree.nodes.comments",
  techtreeActivityList: "techtree.activity.list",
  techtreeSearchQuery: "techtree.search.query",
  techtreeNodesWorkPacket: "techtree.nodes.workPacket",
  techtreeNodesCreate: "techtree.nodes.create",
  techtreeCommentsCreate: "techtree.comments.create",
  techtreeWatchCreate: "techtree.watch.create",
  techtreeWatchDelete: "techtree.watch.delete",
  techtreeWatchList: "techtree.watch.list",
  techtreeStarsCreate: "techtree.stars.create",
  techtreeStarsDelete: "techtree.stars.delete",
  techtreeInboxGet: "techtree.inbox.get",
  techtreeOpportunitiesList: "techtree.opportunities.list",
  techtreeTrollboxHistory: "techtree.trollbox.history",
  techtreeTrollboxPost: "techtree.trollbox.post",
  gossipsubStatus: "gossipsub.status",
  xmtpStatus: "xmtp.status",
} as const satisfies Record<string, RegentRpcMethod>;

export const REGENT_RPC_METHOD_SET = new Set<RegentRpcMethod>(
  Object.values(REGENT_RPC_METHODS),
);
