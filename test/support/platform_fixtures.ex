defmodule TechTree.PlatformFixtures do
  @moduledoc false

  alias TechTree.Platform.{
    Agent,
    BasenameMintAllowance,
    BasenamePaymentCredit,
    EnsSubnameClaim,
    ExplorerTile,
    NameClaim,
    RedeemClaim
  }

  alias TechTree.Repo

  def agent_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        slug: unique_value("agent"),
        source: "fixture",
        display_name: "Fixture Agent",
        summary: "Imported agent fixture",
        status: "active",
        owner_address: unique_address(),
        feature_tags: ["creator"]
      })

    %Agent{}
    |> Agent.changeset(attrs)
    |> Repo.insert!()
  end

  def explorer_tile_fixture(attrs \\ %{}) do
    index = System.unique_integer([:positive])

    attrs =
      Enum.into(attrs, %{
        coord_key: "#{index}:#{index}",
        x: index,
        y: index,
        title: "Tile #{index}",
        summary: "Imported explorer tile fixture",
        shader_key: "signal-bloom",
        terrain: "land",
        unlock_status: "imported"
      })

    %ExplorerTile{}
    |> ExplorerTile.changeset(attrs)
    |> Repo.insert!()
  end

  def name_claim_fixture(attrs \\ %{}) do
    label = unique_value("name")

    attrs =
      Enum.into(attrs, %{
        label: label,
        fqdn: "#{label}.agent.ethereum.eth",
        owner_address: unique_address(),
        status: "claimed",
        source: "fixture"
      })

    %NameClaim{}
    |> NameClaim.changeset(attrs)
    |> Repo.insert!()
  end

  def basename_mint_allowance_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        parent_node: unique_value("parent-node"),
        parent_name: "agent.ethereum.eth",
        address: unique_address(),
        snapshot_block_number: System.unique_integer([:positive]),
        snapshot_total: 2,
        free_mints_used: 1
      })

    %BasenameMintAllowance{}
    |> BasenameMintAllowance.changeset(attrs)
    |> Repo.insert!()
  end

  def basename_payment_credit_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        parent_node: unique_value("parent-node"),
        parent_name: "agent.ethereum.eth",
        address: unique_address(),
        payment_tx_hash: unique_hash(),
        payment_chain_id: 84_532,
        price_wei: Decimal.new("100000000000000")
      })

    %BasenamePaymentCredit{}
    |> BasenamePaymentCredit.changeset(attrs)
    |> Repo.insert!()
  end

  def ens_subname_claim_fixture(attrs \\ %{}) do
    label = unique_value("ens")

    attrs =
      Enum.into(attrs, %{
        config_ref: unique_value("config"),
        owner_address: unique_address(),
        label: label,
        fqdn: "#{label}.agent.ethereum.eth",
        reservation_status: "reserved",
        mint_status: "pending"
      })

    %EnsSubnameClaim{}
    |> EnsSubnameClaim.changeset(attrs)
    |> Repo.insert!()
  end

  def redeem_claim_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        wallet_address: unique_address(),
        source_collection: "Regent Genesis",
        token_id: Decimal.new(System.unique_integer([:positive])),
        tx_hash: unique_hash(),
        status: "indexed",
        source: "fixture"
      })

    %RedeemClaim{}
    |> RedeemClaim.changeset(attrs)
    |> Repo.insert!()
  end

  defp unique_value(prefix) do
    "#{prefix}-#{System.unique_integer([:positive])}"
  end

  defp unique_address do
    suffix =
      System.unique_integer([:positive])
      |> Integer.to_string(16)
      |> String.pad_leading(40, "0")
      |> String.slice(-40, 40)

    "0x" <> suffix
  end

  defp unique_hash do
    suffix =
      System.unique_integer([:positive])
      |> Integer.to_string(16)
      |> String.pad_leading(64, "0")
      |> String.slice(-64, 64)

    "0x" <> suffix
  end
end
