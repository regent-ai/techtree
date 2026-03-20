defmodule TechTreeWeb.PlatformAuthControllerTest do
  use TechTreeWeb.ConnCase, async: false

  import Phoenix.Controller, only: [get_csrf_token: 0]
  import TechTree.PhaseDApiSupport

  alias TechTree.Accounts

  setup do
    privy = setup_privy_config!()

    on_exit(fn ->
      privy.restore.()
    end)

    {:ok, privy: privy}
  end

  test "POST /api/platform/auth/privy/session verifies token and writes session", %{
    conn: conn,
    privy: privy
  } do
    conn =
      conn
      |> csrf_json_conn()
      |> with_privy_bearer("privy-platform-user", privy.app_id, privy.private_pem)
      |> post("/api/platform/auth/privy/session", %{
        "display_name" => "Platform User",
        "wallet_address" => "0x1234567890123456789012345678901234567890"
      })

    assert %{"ok" => true, "human" => %{"privy_user_id" => "privy-platform-user"}} =
             json_response(conn, 200)

    assert get_session(conn, :privy_user_id) == "privy-platform-user"
  end

  test "POST /api/platform/auth/privy/session ignores malformed wallet addresses", %{
    conn: conn,
    privy: privy
  } do
    conn =
      conn
      |> csrf_json_conn()
      |> with_privy_bearer("privy-platform-bad-wallet", privy.app_id, privy.private_pem)
      |> post("/api/platform/auth/privy/session", %{
        "display_name" => "  Platform User  ",
        "wallet_address" => "not-a-wallet"
      })

    assert %{
             "ok" => true,
             "human" => %{
               "privy_user_id" => "privy-platform-bad-wallet",
               "wallet_address" => nil,
               "display_name" => "Platform User"
             }
           } = json_response(conn, 200)
  end

  test "POST /api/platform/auth/privy/session rejects banned humans", %{conn: conn, privy: privy} do
    {:ok, _human} =
      Accounts.upsert_human_by_privy_id("privy-platform-banned", %{
        "display_name" => "Banned Platform User",
        "role" => "banned"
      })

    conn =
      conn
      |> csrf_json_conn()
      |> with_privy_bearer("privy-platform-banned", privy.app_id, privy.private_pem)
      |> post("/api/platform/auth/privy/session", %{
        "display_name" => "Banned Platform User",
        "wallet_address" => "0x1234567890123456789012345678901234567890"
      })

    assert %{"ok" => false, "error" => %{"code" => "human_banned"}} = json_response(conn, 403)
    refute get_session(conn, :privy_user_id)
  end

  test "DELETE /api/platform/auth/privy/session clears the browser session", %{conn: conn} do
    conn =
      conn
      |> Plug.Test.init_test_session(%{privy_user_id: "privy-platform-user"})
      |> csrf_json_conn()
      |> delete("/api/platform/auth/privy/session")

    assert %{"ok" => true} = json_response(conn, 200)
    assert conn.resp_cookies["_tech_tree_key"].max_age == 0
  end

  test "POST /api/platform/auth/privy/session rejects missing bearer tokens", %{conn: conn} do
    conn =
      conn
      |> csrf_json_conn()
      |> post("/api/platform/auth/privy/session", %{"display_name" => "No Token"})

    assert %{"ok" => false, "error" => %{"code" => "privy_required"}} = json_response(conn, 401)
  end

  defp csrf_json_conn(conn) do
    conn
    |> get("/platform")
    |> recycle()
    |> put_req_header("x-csrf-token", get_csrf_token())
    |> put_req_header("accept", "application/json")
  end
end
