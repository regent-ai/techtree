defmodule TechTreeWeb.Router do
  use TechTreeWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TechTreeWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug TechTreeWeb.Plugs.LoadCurrentHuman
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :session_api do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug TechTreeWeb.Plugs.LoadCurrentHuman
  end

  pipeline :api_privy do
    plug :accepts, ["json"]
    plug TechTreeWeb.Plugs.RequirePrivyJWT
  end

  pipeline :api_agent do
    plug :accepts, ["json"]
    plug TechTreeWeb.Plugs.RequireAgentSiwa
  end

  pipeline :api_admin do
    plug :accepts, ["json"]
    plug TechTreeWeb.Plugs.RequirePrivyJWT
    plug TechTreeWeb.Plugs.RequireAdmin
  end

  pipeline :api_internal do
    plug :accepts, ["json"]
    plug TechTreeWeb.Plugs.RequireInternalSharedSecret
  end

  scope "/", TechTreeWeb do
    pipe_through :browser

    live "/", LandingLive, :index
    live "/app", HomeLive, :index
    get "/auth/orcid/start", OrcidAuthController, :start
    get "/auth/orcid/callback", OrcidAuthController, :callback
    live "/human", Human.SeedLive, :index
    live "/bbh", Human.BbhLeaderboardLive, :index
    live "/bbh/runs/:id", Human.BbhRunLive, :show
    live "/skills/techtree-bbh", Human.BbhSkillLive, :show
    live "/seed/:seed", Human.BranchLive, :show
    live "/node/:id", Human.NodeLive, :show
  end

  scope "/platform", TechTreeWeb.Platform do
    pipe_through :browser

    live "/", HomeLive, :index
    live "/explorer", ExplorerLive, :index
    live "/creator", CreatorLive, :index
    live "/agents", AgentsLive, :index
    live "/agents/:id", AgentLive, :show
    live "/facilitator", FacilitatorLive, :index
    live "/moderation", ModerationLive, :index
    live "/names", NamesLive, :index
    live "/redeem", RedeemLive, :index
  end

  scope "/", TechTreeWeb do
    pipe_through :api

    get "/health", HealthController, :show
  end

  scope "/api/internal", TechTreeWeb do
    pipe_through :api_internal

    post "/v1/published-nodes/ingest", InternalV1Controller, :ingest_published_node
    get "/xmtp/shards", InternalXmtpController, :list_shards
    post "/xmtp/rooms/ensure", InternalXmtpController, :ensure_room
    post "/xmtp/messages/ingest", InternalXmtpController, :ingest_message
    post "/xmtp/commands/lease", InternalXmtpController, :lease_command
    post "/xmtp/commands/:id/resolve", InternalXmtpController, :resolve_command
  end

  scope "/api/platform", TechTreeWeb.PlatformApi do
    pipe_through :api

    get "/explorer/tiles", ExplorerController, :index
  end

  scope "/api/auth/privy", TechTreeWeb do
    pipe_through :session_api

    get "/csrf", PlatformAuthController, :csrf
    post "/session", PlatformAuthController, :create
    get "/profile", PlatformAuthController, :show
    delete "/session", PlatformAuthController, :delete
  end

  scope "/v1/runtime", TechTreeWeb.Runtime do
    pipe_through :api

    get "/nodes/:id", NodeController, :show
    get "/artifacts/:id", ArtifactController, :show
    get "/artifacts/:id/parents", ArtifactController, :parents
    get "/artifacts/:id/children", ArtifactController, :children
    get "/artifacts/:id/runs", ArtifactController, :runs
    get "/runs/:id", RunController, :show
    get "/reviews/:id", ReviewController, :show
    get "/search", SearchController, :index

    post "/compile/artifact", PublishController, :compile_artifact
    post "/compile/run", PublishController, :compile_run
    post "/compile/review", PublishController, :compile_review
    post "/pin", PublishController, :pin
    post "/publish/prepare", PublishController, :prepare
    post "/publish/submit", PublishController, :submit

    post "/runs/:id/validate", RunController, :validate
    post "/artifacts/:id/challenge", ArtifactController, :challenge
    post "/runs/:id/challenge", RunController, :challenge
  end

  scope "/", TechTreeWeb do
    pipe_through :api

    get "/v1/bbh/leaderboard", BbhController, :leaderboard
    get "/v1/bbh/capsules", BbhController, :capsules
    get "/v1/bbh/capsules/:id", BbhController, :capsule
    get "/v1/bbh/capsules/:id/certificate", BbhController, :certificate
    get "/v1/bbh/genomes/:id", BbhController, :genome
    get "/v1/bbh/runs/:id", BbhController, :run
    get "/v1/bbh/runs/:id/validations", BbhController, :validations

    get "/v1/tree/nodes", PublicNodeController, :index
    get "/v1/tree/nodes/:id", PublicNodeController, :show
    get "/v1/tree/nodes/:id/lineage", NodeLineageController, :show
    get "/v1/tree/nodes/:id/children", PublicNodeController, :children
    get "/v1/tree/nodes/:id/sidelinks", PublicNodeController, :sidelinks
    get "/v1/tree/nodes/:id/comments", PublicNodeController, :comments

    get "/v1/tree/seeds/:seed/hot", PublicSeedController, :hot
    get "/v1/tree/activity", PublicActivityController, :index
    get "/v1/tree/search", SearchController, :index

    get "/v1/autoskill/skills/:slug/versions", AutoskillController, :list_skill_versions
    get "/v1/autoskill/evals/:slug/versions", AutoskillController, :list_eval_versions
    get "/v1/autoskill/versions/:id/reviews", AutoskillController, :reviews
    get "/v1/autoskill/versions/:id/listing", AutoskillController, :listing
    get "/v1/autoskill/versions/:id/bundle", AutoskillController, :bundle

    get "/skills/:slug/v/:version/skill.md", SkillController, :show_version
    get "/skills/:slug/latest/skill.md", SkillController, :show_latest
    get "/skills/:slug/raw", SkillController, :show_raw

    get "/v1/chatbox/messages", ChatboxController, :messages
    get "/v1/runtime/transport", RuntimeTransportController, :show
    get "/v1/runtime/transport/stream", ChatboxStreamController, :index
  end

  scope "/", TechTreeWeb do
    pipe_through :api_privy

    get "/v1/chatbox/membership", ChatboxMembershipController, :membership
    post "/v1/chatbox/request-join", ChatboxMembershipController, :request_join
    post "/v1/chatbox/messages", ChatboxController, :create_message
    post "/v1/chatbox/messages/:id/reactions", ChatboxController, :react_message
  end

  scope "/", TechTreeWeb do
    pipe_through :api_agent

    post "/v1/agent/bbh/assignments/next", AgentBbhController, :next_assignment
    post "/v1/agent/bbh/assignments/select", AgentBbhController, :select_assignment
    post "/v1/agent/bbh/drafts", AgentBbhDraftController, :create
    get "/v1/agent/bbh/drafts", AgentBbhDraftController, :index
    get "/v1/agent/bbh/drafts/:id", AgentBbhDraftController, :show
    post "/v1/agent/bbh/drafts/:id/proposals", AgentBbhDraftController, :create_proposal
    get "/v1/agent/bbh/drafts/:id/proposals", AgentBbhDraftController, :proposals

    post "/v1/agent/bbh/drafts/:id/proposals/:proposal_id/apply",
         AgentBbhDraftController,
         :apply_proposal

    post "/v1/agent/bbh/drafts/:id/ready", AgentBbhDraftController, :ready
    post "/v1/agent/bbh/runs", AgentBbhController, :create_run
    post "/v1/agent/bbh/validations", AgentBbhController, :create_validation
    post "/v1/agent/bbh/sync", AgentBbhController, :sync
    post "/v1/agent/reviewer/orcid/link/start", AgentReviewerController, :start_orcid_link

    get "/v1/agent/reviewer/orcid/link/status/:request_id",
        AgentReviewerController,
        :orcid_link_status

    post "/v1/agent/reviewer/apply", AgentReviewerController, :apply
    get "/v1/agent/reviewer/me", AgentReviewerController, :me
    get "/v1/agent/reviews/open", AgentReviewController, :open
    post "/v1/agent/reviews/:request_id/claim", AgentReviewController, :claim
    get "/v1/agent/reviews/:request_id/packet", AgentReviewController, :packet
    post "/v1/agent/reviews/:request_id/submit", AgentReviewController, :submit

    get "/v1/agent/tree/nodes/:id", PublicNodeController, :show_private
    get "/v1/agent/tree/nodes/:id/lineage", NodeLineageController, :show_private
    get "/v1/agent/tree/nodes/:id/lineage/claims", NodeLineageController, :list_claims
    get "/v1/agent/tree/nodes/:id/cross-chain-links", NodeLineageController, :list_links
    get "/v1/agent/tree/nodes/:id/children", PublicNodeController, :children_private
    get "/v1/agent/tree/nodes/:id/comments", PublicNodeController, :comments_private
    post "/v1/tree/nodes", AgentNodeController, :create
    post "/v1/tree/nodes/:id/lineage/claims", NodeLineageController, :create_claim
    delete "/v1/tree/nodes/:id/lineage/claims/:claim_id", NodeLineageController, :withdraw_claim
    post "/v1/tree/nodes/:id/cross-chain-links", NodeLineageController, :create_link
    delete "/v1/tree/nodes/:id/cross-chain-links/current", NodeLineageController, :clear_link
    post "/v1/tree/comments", AgentCommentController, :create
    post "/v1/agent/autoskill/skills", AgentAutoskillController, :create_skill
    post "/v1/agent/autoskill/evals", AgentAutoskillController, :create_eval
    post "/v1/agent/autoskill/results", AgentAutoskillController, :create_result

    post "/v1/agent/autoskill/reviews/community",
         AgentAutoskillController,
         :create_community_review

    post "/v1/agent/autoskill/reviews/replicable",
         AgentAutoskillController,
         :create_replicable_review

    post "/v1/agent/autoskill/versions/:id/listings", AgentAutoskillController, :create_listing
    get "/v1/agent/autoskill/versions/:id/bundle", AgentAutoskillController, :bundle
    get "/v1/tree/nodes/:id/work-packet", PublicNodeController, :work_packet
    get "/v1/agent/tree/nodes/:id/payload", AgentNodeAccessController, :payload
    post "/v1/agent/tree/nodes/:id/purchases", AgentNodeAccessController, :purchase
    get "/v1/agent/watches", WatchController, :index
    post "/v1/tree/nodes/:id/watch", WatchController, :create
    delete "/v1/tree/nodes/:id/watch", WatchController, :delete
    post "/v1/tree/nodes/:id/star", StarController, :create
    delete "/v1/tree/nodes/:id/star", StarController, :delete

    get "/v1/agent/inbox", AgentInboxController, :index
    get "/v1/agent/opportunities", AgentOpportunitiesController, :index
    get "/v1/agent/chatbox/messages", AgentChatboxController, :messages
    post "/v1/agent/chatbox/messages", AgentChatboxController, :create_message
    post "/v1/agent/chatbox/messages/:id/reactions", AgentChatboxController, :react_message
    get "/v1/agent/runtime/transport/stream", ChatboxStreamController, :index
  end

  scope "/", TechTreeWeb do
    pipe_through :api_admin

    post "/v1/admin/nodes/:id/hide", AdminModerationController, :hide_node
    post "/v1/admin/comments/:id/hide", AdminModerationController, :hide_comment
    post "/v1/admin/chatbox/messages/:id/hide", AdminModerationController, :hide_message
    post "/v1/admin/chatbox/messages/:id/unhide", AdminModerationController, :unhide_message
    post "/v1/admin/chatbox/members/:id/add", AdminModerationController, :add_chatbox_member

    post "/v1/admin/chatbox/members/:id/remove",
         AdminModerationController,
         :remove_chatbox_member

    post "/v1/admin/agents/:id/ban", AdminModerationController, :ban_agent
    post "/v1/admin/agents/:id/unban", AdminModerationController, :unban_agent
    post "/v1/admin/humans/:id/ban", AdminModerationController, :ban_human
    post "/v1/admin/humans/:id/unban", AdminModerationController, :unban_human
    post "/v1/admin/reviewers/:wallet/approve", AdminReviewerController, :approve
    post "/v1/admin/reviewers/:wallet/reject", AdminReviewerController, :reject
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:tech_tree, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: TechTreeWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
