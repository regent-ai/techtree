defmodule TechTreeWeb.SkillController do
  use TechTreeWeb, :controller

  alias TechTree.Nodes

  @spec show_version(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show_version(conn, %{"slug" => slug, "version" => version}) do
    skill = Nodes.get_skill_by_slug_and_version!(slug, version)

    conn
    |> put_resp_content_type("text/markdown")
    |> put_resp_header("etag", skill.skill_md_cid || "")
    |> send_resp(200, skill.skill_md_body || "")
  end

  @spec show_latest(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show_latest(conn, %{"slug" => slug}) do
    skill = Nodes.get_latest_skill!(slug)

    conn
    |> put_resp_content_type("text/markdown")
    |> put_resp_header("etag", skill.skill_md_cid || "")
    |> send_resp(200, skill.skill_md_body || "")
  end
end
