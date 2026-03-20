defmodule TechTreeWeb.RequireInternalSharedSecretTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias TechTreeWeb.Plugs.RequireInternalSharedSecret

  setup do
    original_secret = Application.get_env(:tech_tree, :internal_shared_secret, "")
    original_runtime_env = Application.get_env(:tech_tree, :runtime_env, :dev)

    on_exit(fn ->
      Application.put_env(:tech_tree, :internal_shared_secret, original_secret)
      Application.put_env(:tech_tree, :runtime_env, original_runtime_env)
    end)

    :ok
  end

  test "rejects requests when the internal shared secret is missing outside test" do
    Application.put_env(:tech_tree, :runtime_env, :dev)
    Application.put_env(:tech_tree, :internal_shared_secret, "")

    conn =
      conn(:post, "/api/internal/example", "{}")
      |> put_req_header("content-type", "application/json")
      |> RequireInternalSharedSecret.call([])

    assert conn.halted
    assert conn.status == 401
  end

  test "allows requests with the expected shared secret" do
    Application.put_env(:tech_tree, :runtime_env, :dev)
    Application.put_env(:tech_tree, :internal_shared_secret, "internal-secret")

    conn =
      conn(:post, "/api/internal/example", "{}")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-tech-tree-secret", "internal-secret")
      |> RequireInternalSharedSecret.call([])

    refute conn.halted
  end

  test "allows missing secret only in test runtime" do
    Application.put_env(:tech_tree, :runtime_env, :test)
    Application.put_env(:tech_tree, :internal_shared_secret, "")

    conn =
      conn(:post, "/api/internal/example", "{}")
      |> put_req_header("content-type", "application/json")
      |> RequireInternalSharedSecret.call([])

    refute conn.halted
  end
end
