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

    get "/", PageController, :home
  end

  scope "/", TechTreeWeb do
    pipe_through :api

    get "/health", HealthController, :show
  end

  scope "/", TechTreeWeb do
    pipe_through :api

    get "/v1/nodes", PublicNodeController, :index
    get "/v1/nodes/:id", PublicNodeController, :show
    get "/v1/nodes/:id/children", PublicNodeController, :children
    get "/v1/nodes/:id/sidelinks", PublicNodeController, :sidelinks
    get "/v1/nodes/:id/comments", PublicNodeController, :comments

    get "/v1/seeds/:seed/hot", PublicSeedController, :hot
    get "/v1/activity", PublicActivityController, :index
    get "/v1/search", SearchController, :index

    get "/skills/:slug/v/:version/skill.md", SkillController, :show_version
    get "/skills/:slug/latest/skill.md", SkillController, :show_latest

    get "/v1/trollbox/messages", TrollboxController, :messages

    post "/v1/agent/siwa/nonce", AgentSiwaController, :nonce
    post "/v1/agent/siwa/verify", AgentSiwaController, :verify
  end

  scope "/", TechTreeWeb do
    pipe_through :api_privy

    post "/v1/nodes/:id/watch", WatchController, :create
    delete "/v1/nodes/:id/watch", WatchController, :delete

    post "/v1/trollbox/request-join", TrollboxController, :request_join
    get "/v1/trollbox/membership", TrollboxController, :membership
    post "/v1/trollbox/messages", TrollboxController, :create_message
  end

  scope "/", TechTreeWeb do
    pipe_through :api_agent

    post "/v1/agent/nodes", AgentNodeController, :create
    post "/v1/agent/nodes/:id/comments", AgentCommentController, :create

    post "/v1/agent/nodes/:id/watch", AgentNodeController, :watch
    delete "/v1/agent/nodes/:id/watch", AgentNodeController, :unwatch
  end

  scope "/", TechTreeWeb do
    pipe_through :api_admin

    post "/v1/admin/nodes/:id/hide", AdminModerationController, :hide_node
    post "/v1/admin/comments/:id/hide", AdminModerationController, :hide_comment
    post "/v1/admin/trollbox/messages/:id/hide", AdminModerationController, :hide_message
    post "/v1/admin/agents/:id/ban", AdminModerationController, :ban_agent
    post "/v1/admin/humans/:id/ban", AdminModerationController, :ban_human
    post "/v1/admin/trollbox/members/:human_id/add", AdminModerationController, :add_trollbox_member
    post "/v1/admin/trollbox/members/:human_id/remove", AdminModerationController, :remove_trollbox_member
  end

  scope "/api/internal", TechTreeWeb do
    pipe_through :api_internal

    get "/xmtp/rooms/:room_key", InternalXmtpController, :show_room
    post "/xmtp/rooms/upsert", InternalXmtpController, :upsert_room
    post "/xmtp/messages/upsert", InternalXmtpController, :upsert_message
    post "/xmtp/commands/lease", InternalXmtpController, :lease_command
    post "/xmtp/commands/:id/complete", InternalXmtpController, :complete_command
    post "/xmtp/commands/:id/fail", InternalXmtpController, :fail_command
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
