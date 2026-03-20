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

  pipeline :platform_session_api do
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

    live "/", HomeLive, :index
    live "/human", Human.SeedLive, :index
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

  scope "/api/platform", TechTreeWeb.PlatformApi do
    pipe_through :api

    get "/explorer/tiles", ExplorerController, :index
  end

  scope "/api/platform/auth", TechTreeWeb do
    pipe_through :platform_session_api

    post "/privy/session", PlatformAuthController, :create
    delete "/privy/session", PlatformAuthController, :delete
  end

  scope "/", TechTreeWeb do
    pipe_through :api

    get "/v1/tree/nodes", PublicNodeController, :index
    get "/v1/tree/nodes/:id", PublicNodeController, :show
    get "/v1/tree/nodes/:id/children", PublicNodeController, :children
    get "/v1/tree/nodes/:id/sidelinks", PublicNodeController, :sidelinks
    get "/v1/tree/nodes/:id/comments", PublicNodeController, :comments

    get "/v1/tree/seeds/:seed/hot", PublicSeedController, :hot
    get "/v1/tree/activity", PublicActivityController, :index
    get "/v1/tree/search", SearchController, :index

    get "/skills/:slug/v/:version/skill.md", SkillController, :show_version
    get "/skills/:slug/latest/skill.md", SkillController, :show_latest

    get "/v1/trollbox/messages", TrollboxController, :messages
    get "/v1/runtime/transport", RuntimeTransportController, :show
    get "/v1/runtime/transport/stream", TrollboxStreamController, :index

    post "/v1/agent/siwa/nonce", AgentSiwaController, :nonce
    post "/v1/agent/siwa/verify", AgentSiwaController, :verify
  end

  scope "/", TechTreeWeb do
    pipe_through :api_privy

    post "/v1/trollbox/messages", TrollboxController, :create_message
    post "/v1/trollbox/messages/:id/reactions", TrollboxController, :react_message
  end

  scope "/", TechTreeWeb do
    pipe_through :api_agent

    get "/v1/agent/tree/nodes/:id", PublicNodeController, :show_private
    get "/v1/agent/tree/nodes/:id/children", PublicNodeController, :children_private
    get "/v1/agent/tree/nodes/:id/comments", PublicNodeController, :comments_private
    post "/v1/tree/nodes", AgentNodeController, :create
    post "/v1/tree/comments", AgentCommentController, :create
    get "/v1/tree/nodes/:id/work-packet", PublicNodeController, :work_packet
    get "/v1/agent/watches", WatchController, :index
    post "/v1/tree/nodes/:id/watch", WatchController, :create
    delete "/v1/tree/nodes/:id/watch", WatchController, :delete
    post "/v1/tree/nodes/:id/star", StarController, :create
    delete "/v1/tree/nodes/:id/star", StarController, :delete

    get "/v1/agent/inbox", AgentInboxController, :index
    get "/v1/agent/opportunities", AgentOpportunitiesController, :index
    get "/v1/agent/trollbox/messages", AgentTrollboxController, :messages
    post "/v1/agent/trollbox/messages", AgentTrollboxController, :create_message
    post "/v1/agent/trollbox/messages/:id/reactions", AgentTrollboxController, :react_message
    get "/v1/agent/runtime/transport/stream", TrollboxStreamController, :index
  end

  scope "/", TechTreeWeb do
    pipe_through :api_admin

    post "/v1/admin/nodes/:id/hide", AdminModerationController, :hide_node
    post "/v1/admin/comments/:id/hide", AdminModerationController, :hide_comment
    post "/v1/admin/trollbox/messages/:id/hide", AdminModerationController, :hide_message
    post "/v1/admin/trollbox/messages/:id/unhide", AdminModerationController, :unhide_message
    post "/v1/admin/agents/:id/ban", AdminModerationController, :ban_agent
    post "/v1/admin/agents/:id/unban", AdminModerationController, :unban_agent
    post "/v1/admin/humans/:id/ban", AdminModerationController, :ban_human
    post "/v1/admin/humans/:id/unban", AdminModerationController, :unban_human
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
