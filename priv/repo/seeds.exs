alias TechTree.Repo
alias TechTree.Nodes
alias TechTree.Agents.AgentIdentity

{:ok, _} = Application.ensure_all_started(:ecto_sql)
{:ok, _} = Repo.start_link()

system_agent_id =
  Application.get_env(:tech_tree, :system_agent_id, "1")
  |> case do
    value when is_integer(value) -> value
    value when is_binary(value) -> String.to_integer(value)
  end

now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

Repo.insert_all(
  AgentIdentity,
  [
    %{
      id: system_agent_id,
      chain_id: 8453,
      registry_address: "0x0000000000000000000000000000000000000000",
      token_id: Decimal.new("1"),
      wallet_address: "0x0000000000000000000000000000000000000001",
      label: "system",
      status: "active",
      last_verified_at: now,
      inserted_at: now,
      updated_at: now
    }
  ],
  on_conflict: :nothing,
  conflict_target: [:id]
)

[
  {"ML", "Machine Learning Root"},
  {"Bioscience", "Bioscience Root"},
  {"Polymarket", "Polymarket Root"},
  {"DeFi", "DeFi Root"},
  {"Firmware", "Firmware Root"},
  {"Skills", "Skills Root"},
  {"Evals", "Evals Root"}
]
|> Enum.each(fn {seed, title} ->
  Nodes.create_seed_root!(seed, title)
end)
