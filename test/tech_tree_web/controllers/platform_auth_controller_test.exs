defmodule TechTreeWeb.PlatformAuthControllerTest do
  use TechTreeWeb.ConnCase, async: false

  import Phoenix.Controller, only: [get_csrf_token: 0]
  import TechTree.PhaseDApiSupport

  alias TechTree.{Accounts, XmtpIdentity}

  setup do
    privy = setup_privy_config!()

    on_exit(fn ->
      privy.restore.()
    end)

    {:ok, privy: privy}
  end

  test "POST /api/auth/privy/session starts wallet-backed room setup and writes session",
       %{
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
               "wallet_address" => "0x1234567890123456789012345678901234567890",
               "xmtp_inbox_id" => nil
             },
             "xmtp" => %{
               "status" => "signature_required",
               "client_id" => client_id,
               "signature_request_id" => signature_request_id,
               "signature_text" => signature_text
             }
           } =
             json_response(conn, 200)

    assert is_binary(client_id) and client_id != ""
    assert is_binary(signature_request_id) and signature_request_id != ""
    assert is_binary(signature_text) and signature_text != ""
    assert get_session(conn, :privy_user_id) == "privy-platform-user"
  end

  test "POST /api/auth/privy/session keeps the stored deterministic XMTP inbox and normalizes wallet casing",
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

  test "TechTree.XmtpIdentity.ensure_identity treats the deterministic inbox id as ready", %{
    privy: _privy
  } do
    wallet_address = "0x3234567890abcdef1234567890abcdef12345678"
    inbox_id = deterministic_inbox_id(wallet_address)

    {:ok, human} =
      Accounts.upsert_human_by_privy_id("privy-identity-ready", %{
        "display_name" => "Platform User",
        "wallet_address" => wallet_address,
        "xmtp_inbox_id" => inbox_id
      })

    assert {:ok, {:ready, ready_human}} = XmtpIdentity.ensure_identity(human)
    assert ready_human.id == human.id
    assert ready_human.xmtp_inbox_id == inbox_id
  end

  test "TechTree.XmtpIdentity.ready_inbox_id rejects a saved inbox id that does not belong to the wallet",
       %{privy: _privy} do
    wallet_address = "0x3334567890abcdef1234567890abcdef12345678"

    {:ok, human} =
      Accounts.upsert_human_by_privy_id("privy-identity-stale", %{
        "display_name" => "Platform User",
        "wallet_address" => wallet_address,
        "xmtp_inbox_id" => "stale-inbox-id"
      })

    assert {:error, :xmtp_identity_required} = XmtpIdentity.ready_inbox_id(human)
  end

  test "POST /api/auth/privy/session does not become ready before XMTP completion", %{
    conn: conn,
    privy: privy
  } do
    first_conn =
      conn
      |> csrf_json_conn()
      |> with_privy_bearer("privy-platform-pending", privy.app_id, privy.private_pem)
      |> post("/api/auth/privy/session", %{
        "display_name" => "Platform User",
        "wallet_address" => "0x4234567890abcdef1234567890abcdef12345678"
      })

    assert %{
             "ok" => true,
             "human" => %{"xmtp_inbox_id" => nil},
             "xmtp" => %{
               "status" => "signature_required",
               "client_id" => first_client_id,
               "signature_request_id" => first_request_id
             }
           } = json_response(first_conn, 200)

    assert is_binary(first_client_id) and first_client_id != ""
    assert is_binary(first_request_id) and first_request_id != ""

    second_conn =
      conn
      |> csrf_json_conn()
      |> with_privy_bearer("privy-platform-pending", privy.app_id, privy.private_pem)
      |> post("/api/auth/privy/session", %{
        "display_name" => "Platform User",
        "wallet_address" => "0x4234567890abcdef1234567890abcdef12345678"
      })

    assert %{
             "ok" => true,
             "human" => %{"xmtp_inbox_id" => nil},
             "xmtp" => %{
               "status" => "signature_required",
               "client_id" => second_client_id,
               "signature_request_id" => second_request_id
             }
           } = json_response(second_conn, 200)

    assert is_binary(second_client_id) and second_client_id != ""
    assert is_binary(second_request_id) and second_request_id != ""
    refute second_client_id == first_client_id
    refute second_request_id == first_request_id

    assert %TechTree.Accounts.HumanUser{xmtp_inbox_id: nil} =
             Accounts.get_human_by_privy_id("privy-platform-pending")
  end

  test "POST /api/auth/privy/session clears stale inbox ids when the wallet has no XMTP registration",
       %{conn: conn, privy: privy} do
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
             "xmtp" => %{"status" => "signature_required"}
           } = json_response(conn, 200)

    assert %TechTree.Accounts.HumanUser{
             wallet_address: ^wallet_address,
             xmtp_inbox_id: nil
           } = Accounts.get_human_by_privy_id("privy-platform-stale")
  end

  test "POST /api/auth/privy/xmtp/complete stores the real inbox id", %{
    conn: conn,
    privy: privy
  } do
    session_conn =
      conn
      |> csrf_json_conn()
      |> with_privy_bearer("privy-platform-xmtp", privy.app_id, privy.private_pem)
      |> post("/api/auth/privy/session", %{
        "display_name" => "Platform User",
        "wallet_address" => "0x1234567890123456789012345678901234567890"
      })

    assert %{
             "xmtp" => %{
               "status" => "signature_required",
               "client_id" => client_id,
               "signature_request_id" => signature_request_id
             }
           } = json_response(session_conn, 200)

    complete_conn =
      conn
      |> csrf_json_conn()
      |> with_privy_bearer("privy-platform-xmtp", privy.app_id, privy.private_pem)
      |> post("/api/auth/privy/xmtp/complete", %{
        "wallet_address" => "0x1234567890123456789012345678901234567890",
        "client_id" => client_id,
        "signature_request_id" => signature_request_id,
        "signature" => "0xsigned"
      })

    assert %{
             "ok" => true,
             "human" => %{
               "privy_user_id" => "privy-platform-xmtp",
               "xmtp_inbox_id" => inbox_id
             },
             "xmtp" => %{"status" => "ready", "inbox_id" => ready_inbox_id}
           } = json_response(complete_conn, 200)

    assert is_binary(inbox_id) and inbox_id != ""
    assert ready_inbox_id == inbox_id
  end

  test "POST /api/auth/privy/xmtp/complete rejects wallet changes and leaves the stored wallet alone",
       %{conn: conn, privy: privy} do
    {:ok, _human} =
      Accounts.open_privy_session("privy-platform-wallet-lock", %{
        "display_name" => "Platform User",
        "wallet_address" => "0x1234567890123456789012345678901234567890"
      })

    conn =
      conn
      |> csrf_json_conn()
      |> with_privy_bearer("privy-platform-wallet-lock", privy.app_id, privy.private_pem)
      |> post("/api/auth/privy/xmtp/complete", %{
        "wallet_address" => "0xABCDEF1234567890ABCDEF1234567890ABCDEF12",
        "client_id" => "client-1",
        "signature_request_id" => "signature-request-1",
        "signature" => "0xsigned"
      })

    assert %{"ok" => false, "error" => %{"code" => "wallet_address_mismatch"}} =
             json_response(conn, 422)

    assert %TechTree.Accounts.HumanUser{
             wallet_address: "0x1234567890123456789012345678901234567890",
             xmtp_inbox_id: nil
           } = Accounts.get_human_by_privy_id("privy-platform-wallet-lock")
  end

  test "POST /api/auth/privy/xmtp/complete requires an existing wallet setup row", %{
    conn: conn,
    privy: privy
  } do
    conn =
      conn
      |> csrf_json_conn()
      |> with_privy_bearer("privy-platform-missing-setup", privy.app_id, privy.private_pem)
      |> post("/api/auth/privy/xmtp/complete", %{
        "wallet_address" => "0x1234567890123456789012345678901234567890",
        "client_id" => "client-1",
        "signature_request_id" => "signature-request-1",
        "signature" => "0xsigned"
      })

    assert %{"ok" => false, "error" => %{"code" => "xmtp_setup_required"}} =
             json_response(conn, 422)
  end

  test "POST /api/auth/privy/session rejects invalid wallet addresses", %{
    conn: conn,
    privy: privy
  } do
    conn =
      conn
      |> csrf_json_conn()
      |> with_privy_bearer("privy-platform-bad-wallet", privy.app_id, privy.private_pem)
      |> post("/api/auth/privy/session", %{
        "display_name" => "  Platform User  ",
        "wallet_address" => "not-a-wallet"
      })

    assert %{"ok" => false, "error" => %{"code" => "wallet_address_invalid"}} =
             json_response(conn, 422)
  end

  test "POST /api/auth/privy/session rejects banned humans", %{conn: conn, privy: privy} do
    wallet_address = "0x1234567890123456789012345678901234567890"
    inbox_id = deterministic_inbox_id(wallet_address)

    {:ok, _human} =
      Accounts.upsert_human_by_privy_id("privy-platform-banned", %{
        "display_name" => "Banned Platform User",
        "wallet_address" => wallet_address,
        "xmtp_inbox_id" => inbox_id,
        "role" => "banned"
      })

    conn =
      conn
      |> csrf_json_conn()
      |> with_privy_bearer("privy-platform-banned", privy.app_id, privy.private_pem)
      |> post("/api/auth/privy/session", %{
        "display_name" => "Changed Platform User",
        "wallet_address" => "0xABCDEF1234567890ABCDEF1234567890ABCDEF12"
      })

    assert %{"ok" => false, "error" => %{"code" => "human_banned"}} = json_response(conn, 403)
    refute get_session(conn, :privy_user_id)

    assert %TechTree.Accounts.HumanUser{
             display_name: "Banned Platform User",
             wallet_address: ^wallet_address,
             xmtp_inbox_id: ^inbox_id,
             role: "banned"
           } = Accounts.get_human_by_privy_id("privy-platform-banned")
  end

  test "POST /api/auth/privy/xmtp/complete rejects banned humans before changing their row",
       %{conn: conn, privy: privy} do
    wallet_address = "0x1234567890123456789012345678901234567890"
    inbox_id = deterministic_inbox_id(wallet_address)

    {:ok, _human} =
      Accounts.upsert_human_by_privy_id("privy-platform-banned-complete", %{
        "display_name" => "Banned Platform User",
        "wallet_address" => wallet_address,
        "xmtp_inbox_id" => inbox_id,
        "role" => "banned"
      })

    conn =
      conn
      |> csrf_json_conn()
      |> with_privy_bearer("privy-platform-banned-complete", privy.app_id, privy.private_pem)
      |> post("/api/auth/privy/xmtp/complete", %{
        "wallet_address" => "0xABCDEF1234567890ABCDEF1234567890ABCDEF12",
        "client_id" => "client-1",
        "signature_request_id" => "signature-request-1",
        "signature" => "0xsigned"
      })

    assert %{"ok" => false, "error" => %{"code" => "human_banned"}} = json_response(conn, 403)

    assert %TechTree.Accounts.HumanUser{
             display_name: "Banned Platform User",
             wallet_address: ^wallet_address,
             xmtp_inbox_id: ^inbox_id,
             role: "banned"
           } = Accounts.get_human_by_privy_id("privy-platform-banned-complete")
  end

  test "DELETE /api/auth/privy/session clears only the Privy session key", %{conn: conn} do
    conn =
      conn
      |> Plug.Test.init_test_session(%{
        privy_user_id: "privy-platform-user",
        ui_theme: "light"
      })
      |> csrf_json_conn()
      |> delete("/api/auth/privy/session")

    assert %{"ok" => true} = json_response(conn, 200)
    refute get_session(conn, :privy_user_id)
    assert get_session(conn, :ui_theme) == "light"
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
    |> get("/platform")
    |> recycle()
    |> put_req_header("x-csrf-token", get_csrf_token())
    |> put_req_header("accept", "application/json")
  end
end
