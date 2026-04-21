ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(TechTree.Repo, :manual)

{:ok, siwa_socket} =
  :gen_tcp.listen(0, [:binary, packet: :raw, active: false, ip: {127, 0, 0, 1}])

{:ok, siwa_port} = :inet.port(siwa_socket)
:ok = :gen_tcp.close(siwa_socket)

{:ok, _} =
  Agent.start_link(
    fn -> %{status: 200, last_request: nil} end,
    name: TechTreeWeb.TestSupport.SiwaSidecarState
  )

{:ok, _} =
  Bandit.start_link(
    plug: TechTreeWeb.TestSupport.SiwaSidecarStub,
    ip: {127, 0, 0, 1},
    port: siwa_port
  )

Application.put_env(:tech_tree, :siwa,
  internal_url: "http://127.0.0.1:#{siwa_port}",
  shared_secret: "techtree-test-shared-secret"
)
