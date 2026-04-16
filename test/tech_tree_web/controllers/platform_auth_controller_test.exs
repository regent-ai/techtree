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

  test "POST /api/auth/privy/session writes the browser session and returns the human row", %{
    conn: conn,
    privy: privy
  } do
    conn =
      conn
      |> csrf_json_conn()
      |> with_privy_bearer("privy-platform-user", privy.app_id, privy.private_pem)
      |> post("/api/auth/privy/session", %{
        "display_name" => "Platform User",
        "wallet_address" => "0x1234567890123456789012345678901234567890"
      })

    assert %{
             "ok" => true,
             "human" => %{
               "privy_user_id" => "privy-platform-user",
               "display_name" => "Platform User",
               "wallet_address" => "0x1234567890123456789012345678901234567890",
               "xmtp_inbox_id" => nil
             },
             "xmtp" => nil
           } = json_response(conn, 200)

    assert get_session(conn, :privy_user_id) == "privy-platform-user"
  end

  test "POST /api/auth/privy/session keeps a ready inbox for a known wallet and normalizes wallet casing",
       %{conn: conn, privy: privy} do
    wallet_address = "0x1234567890abcdef1234567890abcdef12345678"
    mixed_case_wallet_address = "0x1234567890ABCDEF1234567890ABCDEF12345678"
    real_inbox_id = deterministic_inbox_id(wallet_address)

    {:ok, _human} =
      Accounts.upsert_human_by_privy_id("privy-platform-real", %{
        "display_name" => "Platform User",
        "wallet_address" => wallet_address,
        "xmtp_inbox_id" => real_inbox_id
      })

    conn =
      conn
      |> csrf_json_conn()
      |> with_privy_bearer("privy-platform-real", privy.app_id, privy.private_pem)
      |> post("/api/auth/privy/session", %{
        "display_name" => "Platform User",
        "wallet_address" => mixed_case_wallet_address
      })

    assert %{
             "ok" => true,
             "human" => %{
               "privy_user_id" => "privy-platform-real",
               "wallet_address" => ^wallet_address,
               "xmtp_inbox_id" => ^real_inbox_id
             },
             "xmtp" => %{"status" => "ready", "inbox_id" => ^real_inbox_id}
           } = json_response(conn, 200)

    assert %TechTree.Accounts.HumanUser{
             wallet_address: ^wallet_address,
             xmtp_inbox_id: ^real_inbox_id
           } = Accounts.get_human_by_privy_id("privy-platform-real")
  end

  test "POST /api/auth/privy/session clears a stale inbox when the wallet does not match it", %{
    conn: conn,
    privy: privy
  } do
    wallet_address = "0x2234567890abcdef1234567890abcdef12345678"

    {:ok, _human} =
      Accounts.upsert_human_by_privy_id("privy-platform-stale", %{
        "display_name" => "Platform User",
        "wallet_address" => wallet_address,
        "xmtp_inbox_id" => "stale-inbox-id"
      })

    conn =
      conn
      |> csrf_json_conn()
      |> with_privy_bearer("privy-platform-stale", privy.app_id, privy.private_pem)
      |> post("/api/auth/privy/session", %{
        "display_name" => "Platform User",
        "wallet_address" => wallet_address
      })

    assert %{
             "ok" => true,
             "human" => %{
               "privy_user_id" => "privy-platform-stale",
               "wallet_address" => ^wallet_address,
               "xmtp_inbox_id" => nil
             },
             "xmtp" => nil
           } = json_response(conn, 200)

    assert %TechTree.Accounts.HumanUser{
             wallet_address: ^wallet_address,
             xmtp_inbox_id: nil
           } = Accounts.get_human_by_privy_id("privy-platform-stale")
  end

  test "GET /api/auth/privy/profile returns the current signed-in human", %{
    conn: conn,
    privy: privy
  } do
    ready_wallet = "0x3234567890abcdef1234567890abcdef12345678"
    ready_inbox_id = deterministic_inbox_id(ready_wallet)

    {:ok, _human} =
      Accounts.upsert_human_by_privy_id("privy-platform-profile", %{
        "display_name" => "Profile User",
        "wallet_address" => ready_wallet,
        "xmtp_inbox_id" => ready_inbox_id
      })

    session_conn =
      conn
      |> csrf_json_conn()
      |> with_privy_bearer("privy-platform-profile", privy.app_id, privy.private_pem)
      |> post("/api/auth/privy/session", %{
        "display_name" => "Profile User",
        "wallet_address" => ready_wallet
      })

    profile_conn =
      session_conn
      |> recycle()
      |> put_req_header("accept", "application/json")
      |> get("/api/auth/privy/profile")

    assert %{
             "ok" => true,
             "human" => %{
               "privy_user_id" => "privy-platform-profile",
               "display_name" => "Profile User",
               "wallet_address" => ^ready_wallet,
               "xmtp_inbox_id" => ^ready_inbox_id
             },
             "xmtp" => %{"status" => "ready", "inbox_id" => ^ready_inbox_id}
           } = json_response(profile_conn, 200)
  end

  test "DELETE /api/auth/privy/session clears the signed-in session cookie", %{
    conn: conn,
    privy: privy
  } do
    session_conn =
      conn
      |> csrf_json_conn()
      |> with_privy_bearer("privy-platform-logout", privy.app_id, privy.private_pem)
      |> post("/api/auth/privy/session", %{
        "display_name" => "Logout User",
        "wallet_address" => "0x4234567890abcdef1234567890abcdef12345678"
      })

    assert get_session(session_conn, :privy_user_id) == "privy-platform-logout"

    logout_conn =
      session_conn
      |> csrf_json_conn()
      |> delete("/api/auth/privy/session")

    assert %{"ok" => true} = json_response(logout_conn, 200)
    assert logout_conn.resp_cookies["_tech_tree_key"].max_age == 0

    profile_conn =
      logout_conn
      |> recycle()
      |> put_req_header("accept", "application/json")
      |> get("/api/auth/privy/profile")

    assert %{"ok" => true, "human" => nil, "xmtp" => nil} = json_response(profile_conn, 200)
  end

  test "POST /api/auth/privy/session rejects invalid wallet addresses", %{
    conn: conn,
    privy: privy
  } do
    conn =
      conn
      |> csrf_json_conn()
      |> with_privy_bearer("privy-platform-invalid-wallet", privy.app_id, privy.private_pem)
      |> post("/api/auth/privy/session", %{
        "display_name" => "Platform User",
        "wallet_address" => "not-a-wallet"
      })

    assert %{"ok" => false, "error" => %{"code" => "wallet_address_invalid"}} =
             json_response(conn, 422)
  end

  test "POST /api/auth/privy/session rejects banned humans before changing their row", %{
    conn: conn,
    privy: privy
  } do
    {:ok, banned_human} =
      Accounts.upsert_human_by_privy_id("privy-platform-banned", %{
        "display_name" => "Banned Person",
        "wallet_address" => "0x5234567890abcdef1234567890abcdef12345678",
        "role" => "banned",
        "xmtp_inbox_id" => "inbox-keep-me"
      })

    conn =
      conn
      |> csrf_json_conn()
      |> with_privy_bearer("privy-platform-banned", privy.app_id, privy.private_pem)
      |> post("/api/auth/privy/session", %{
        "display_name" => "Updated Name",
        "wallet_address" => "0x6234567890abcdef1234567890abcdef12345678"
      })

    assert %{"ok" => false, "error" => %{"code" => "human_banned"}} = json_response(conn, 403)

    assert %TechTree.Accounts.HumanUser{
             id: banned_id,
             display_name: "Banned Person",
             wallet_address: "0x5234567890abcdef1234567890abcdef12345678",
             xmtp_inbox_id: "inbox-keep-me",
             role: "banned"
           } = Accounts.get_human_by_privy_id("privy-platform-banned")

    assert banned_id == banned_human.id
  end

  test "POST /api/auth/privy/session rejects missing bearer tokens", %{conn: conn} do
    conn =
      conn
      |> csrf_json_conn()
      |> post("/api/auth/privy/session", %{"display_name" => "No Token"})

    assert %{"ok" => false, "error" => %{"code" => "privy_required"}} = json_response(conn, 401)
  end

  defp csrf_json_conn(conn) do
    conn
    |> recycle()
    |> delete_req_header("accept")
    |> get("/platform")
    |> recycle()
    |> put_req_header("x-csrf-token", get_csrf_token())
    |> put_req_header("accept", "application/json")
  end
end
