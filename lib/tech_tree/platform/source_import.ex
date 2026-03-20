defmodule TechTree.Platform.SourceImport do
  @moduledoc false

  import Ecto.Query

  alias TechTree.Platform.{
    Agent,
    BasenameMintAllowance,
    BasenamePaymentCredit,
    EnsSubnameClaim,
    ExplorerTile,
    ImportRun,
    NameClaim,
    RedeemClaim
  }

  alias TechTree.Repo

  @source "regent-platform"

  def run(opts \\ []) do
    source_database = Keyword.get(opts, :source_database, source_database_url())
    notes = Keyword.get(opts, :notes)

    run =
      %ImportRun{}
      |> ImportRun.changeset(%{
        source: @source,
        source_database: redact_database(source_database),
        notes: notes,
        status: "running"
      })
      |> Repo.insert!()

    counts =
      with {:ok, pid} <- start_source_connection(source_database) do
        try do
          %{
            explorer_tiles: import_explorer_tiles(pid),
            agents: import_agents(pid),
            basename_mints: import_basenames_mints(pid),
            basename_payment_credits: import_basename_payment_credits(pid),
            basename_mint_allowances: import_basename_mint_allowances(pid),
            ens_subname_claims: import_ens_subname_claims(pid),
            redeems: import_redeems(pid)
          }
        after
          GenServer.stop(pid)
        end
      else
        {:error, reason} ->
          Repo.update!(
            ImportRun.changeset(run, %{
              status: "failed",
              notes: "unable to connect to source database: #{inspect(reason)}",
              finished_at: DateTime.utc_now()
            })
          )

          raise "platform import failed: #{inspect(reason)}"
      end

    Repo.update!(
      ImportRun.changeset(run, %{
        status: "completed",
        imported_counts: counts,
        finished_at: DateTime.utc_now()
      })
    )

    counts
  end

  def source_database_url do
    System.get_env("PLATFORM_SOURCE_DATABASE_URL") ||
      System.get_env("SOURCE_PLATFORM_DATABASE_URL")
  end

  defp start_source_connection(nil), do: {:error, :missing_source_database_url}
  defp start_source_connection(""), do: {:error, :missing_source_database_url}

  defp start_source_connection(url) do
    Postgrex.start_link(url: url, prepare: :unnamed, backoff_type: :stop)
  end

  defp import_explorer_tiles(pid) do
    if table_exists?(pid, "explorer_tiles") do
      %{rows: rows} =
        query!(pid, """
        select x, y, owner_address, shader_id, terrain, created_at, payment_credit_id
        from explorer_tiles
        order by created_at desc
        limit 600
        """)

      rows
      |> Enum.map(&map_explorer_tile/1)
      |> upsert_many(ExplorerTile, :coord_key)
    else
      0
    end
  end

  defp import_agents(pid) do
    imported_ironsprite =
      if table_exists?(pid, "ironsprite_agents") do
        %{rows: rows} =
          query!(pid, """
          select agent_id, sprite_name, owner_address, status, gateway_url, chain_id, created_at
          from ironsprite_agents
          order by created_at desc
          limit 400
          """)

        rows
        |> Enum.map(&map_ironsprite_agent/1)
        |> upsert_many(Agent, :slug)
      else
        0
      end

    imported_regentbot =
      if table_exists?(pid, "regentbot_agents") do
        %{rows: rows} =
          query!(pid, """
          select agent_id, owner_address, agent_uri, phala_url, chain_id, created_at
          from regentbot_agents
          order by created_at desc
          limit 400
          """)

        rows
        |> Enum.map(&map_regentbot_agent/1)
        |> upsert_many(Agent, :slug)
      else
        0
      end

    imported_ironsprite + imported_regentbot
  end

  defp import_basenames_mints(pid) do
    if table_exists?(pid, "basenames_mints") do
      %{rows: rows} =
        query!(pid, """
        select label, fqdn, owner_address, tx_hash, ens_fqdn, created_at, is_free
        from basenames_mints
        order by created_at desc
        limit 500
        """)

      rows
      |> Enum.map(&map_name_claim/1)
      |> upsert_many(NameClaim, :fqdn)
    else
      0
    end
  end

  defp import_basename_payment_credits(pid) do
    if table_exists?(pid, "basenames_payment_credits") do
      %{rows: rows} =
        query!(pid, """
        select parent_node, parent_name, address, payment_tx_hash, payment_chain_id, price_wei, consumed_at, consumed_node, consumed_fqdn, created_at
        from basenames_payment_credits
        order by created_at desc
        limit 500
        """)

      rows
      |> Enum.map(&map_basename_payment_credit/1)
      |> upsert_many(BasenamePaymentCredit, [:payment_tx_hash, :payment_chain_id])
    else
      0
    end
  end

  defp import_basename_mint_allowances(pid) do
    if table_exists?(pid, "basenames_mint_allowances") do
      %{rows: rows} =
        query!(pid, """
        select parent_node, parent_name, address, snapshot_block_number, snapshot_total, free_mints_used, created_at
        from basenames_mint_allowances
        order by created_at desc
        limit 500
        """)

      rows
      |> Enum.map(&map_basename_mint_allowance/1)
      |> upsert_many(BasenameMintAllowance, [:parent_node, :address])
    else
      0
    end
  end

  defp import_ens_subname_claims(pid) do
    if table_exists?(pid, "ens_subname_claims") do
      %{rows: rows} =
        query!(pid, """
        select config_id, owner_address, label, fqdn, reservation_status, mint_status, reservation_tx_hash, mint_tx_hash, last_error_code, last_error_message, created_at
        from ens_subname_claims
        order by created_at desc
        limit 500
        """)

      rows
      |> Enum.map(&map_ens_subname_claim/1)
      |> upsert_many(EnsSubnameClaim, :config_ref)
    else
      0
    end
  end

  defp import_redeems(pid) do
    if table_exists?(pid, "redeem_events") do
      %{rows: rows} =
        query!(pid, """
        select wallet_address, source_collection, token_id, tx_hash, created_at
        from redeem_events
        order by created_at desc
        limit 500
        """)

      rows
      |> Enum.map(&map_redeem_claim/1)
      |> upsert_many(RedeemClaim, :tx_hash)
    else
      0
    end
  end

  defp upsert_many([], _module, _unique_field), do: 0

  defp upsert_many(rows, module, unique_field) do
    unique_fields = List.wrap(unique_field)

    Enum.reduce(rows, 0, fn attrs, acc ->
      existing =
        module
        |> where_by_unique_fields(unique_fields, attrs)
        |> Repo.one()

      changeset = module.changeset(existing || struct(module), attrs)

      case Repo.insert_or_update(changeset) do
        {:ok, _record} -> acc + 1
        {:error, _changeset} -> acc
      end
    end)
  end

  defp where_by_unique_fields(query, unique_fields, attrs) do
    Enum.reduce(unique_fields, query, fn field_name, scoped_query ->
      where(scoped_query, [row], field(row, ^field_name) == ^Map.fetch!(attrs, field_name))
    end)
  end

  defp table_exists?(pid, table_name) do
    %{rows: [[exists?]]} =
      query!(
        pid,
        """
        select exists(
          select 1
          from information_schema.tables
          where table_schema = 'public' and table_name = $1
        )
        """,
        [table_name]
      )

    exists?
  end

  defp query!(pid, sql, params \\ []), do: Postgrex.query!(pid, sql, params)

  defp map_explorer_tile([x, y, owner_address, shader_id, terrain, created_at, payment_credit_id]) do
    %{
      coord_key: "#{x}:#{y}",
      x: x,
      y: y,
      title: "Tile #{x},#{y}",
      summary: "Imported explorer tile from the Regent platform surface.",
      shader_key: shader_id || "signal-bloom",
      terrain: terrain || "land",
      unlock_status: "imported",
      owner_address: owner_address,
      source_ref: payment_credit_id && Integer.to_string(payment_credit_id),
      metadata: %{"imported_at" => encode_datetime(created_at)},
      unlocked_at: created_at
    }
  end

  defp map_ironsprite_agent([
         agent_id,
         sprite_name,
         owner_address,
         status,
         gateway_url,
         chain_id,
         created_at
       ]) do
    %{
      slug: "ironsprite-" <> slugify(agent_id),
      source: "ironsprite",
      source_ref: agent_id,
      owner_address: owner_address,
      display_name: sprite_name || agent_id,
      summary: "Imported hosted agent record from ironsprite.",
      status: status || "active",
      external_url: gateway_url,
      chain_id: chain_id,
      feature_tags: ["hosted", "creator"],
      metadata: %{"imported_at" => encode_datetime(created_at)}
    }
  end

  defp map_regentbot_agent([
         agent_id,
         owner_address,
         agent_uri,
         phala_url,
         chain_id,
         created_at
       ]) do
    %{
      slug: "regentbot-" <> slugify(agent_id),
      source: "regentbot",
      source_ref: agent_id,
      owner_address: owner_address,
      display_name: agent_id,
      summary: "Imported Regentbot deployment tracked by the legacy platform.",
      status: "ready",
      agent_uri: agent_uri,
      external_url: phala_url,
      chain_id: chain_id,
      feature_tags: ["hosted", "phala"],
      metadata: %{"imported_at" => encode_datetime(created_at)}
    }
  end

  defp map_name_claim([label, fqdn, owner_address, tx_hash, ens_fqdn, created_at, is_free]) do
    %{
      label: label,
      fqdn: fqdn,
      owner_address: owner_address,
      status: if(is_free, do: "granted", else: "paid"),
      tx_hash: tx_hash,
      ens_fqdn: ens_fqdn,
      source: "basenames",
      metadata: %{"imported_at" => encode_datetime(created_at), "free" => is_free == true}
    }
  end

  defp map_basename_payment_credit([
         parent_node,
         parent_name,
         address,
         payment_tx_hash,
         payment_chain_id,
         price_wei,
         consumed_at,
         consumed_node,
         consumed_fqdn,
         created_at
       ]) do
    %{
      parent_node: parent_node,
      parent_name: parent_name,
      address: address,
      payment_tx_hash: payment_tx_hash,
      payment_chain_id: payment_chain_id,
      price_wei: price_wei,
      consumed_at: consumed_at,
      consumed_node: consumed_node,
      consumed_fqdn: consumed_fqdn,
      metadata: %{"imported_at" => encode_datetime(created_at)}
    }
  end

  defp map_basename_mint_allowance([
         parent_node,
         parent_name,
         address,
         snapshot_block_number,
         snapshot_total,
         free_mints_used,
         created_at
       ]) do
    %{
      parent_node: parent_node,
      parent_name: parent_name,
      address: address,
      snapshot_block_number: snapshot_block_number,
      snapshot_total: snapshot_total || 0,
      free_mints_used: free_mints_used || 0,
      metadata: %{"imported_at" => encode_datetime(created_at)}
    }
  end

  defp map_ens_subname_claim([
         config_id,
         owner_address,
         label,
         fqdn,
         reservation_status,
         mint_status,
         reservation_tx_hash,
         mint_tx_hash,
         last_error_code,
         last_error_message,
         created_at
       ]) do
    %{
      config_ref: config_id,
      owner_address: owner_address,
      label: label,
      fqdn: fqdn,
      reservation_status: reservation_status || "reserved",
      mint_status: mint_status || "pending",
      reservation_tx_hash: reservation_tx_hash,
      mint_tx_hash: mint_tx_hash,
      last_error_code: last_error_code,
      last_error_message: last_error_message,
      metadata: %{"imported_at" => encode_datetime(created_at)}
    }
  end

  defp map_redeem_claim([wallet_address, source_collection, token_id, tx_hash, created_at]) do
    %{
      wallet_address: wallet_address,
      source_collection: source_collection,
      token_id: token_id,
      tx_hash: tx_hash,
      status: "indexed",
      source: "redeem",
      metadata: %{"imported_at" => encode_datetime(created_at)}
    }
  end

  defp slugify(nil), do: "unknown"

  defp slugify(value) do
    value
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
    |> case do
      "" -> "item"
      slug -> slug
    end
  end

  defp encode_datetime(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp encode_datetime(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp encode_datetime(_value), do: nil

  defp redact_database(nil), do: nil

  defp redact_database(value) do
    case URI.parse(value) do
      %URI{host: host, path: path} when is_binary(host) ->
        host <> (path || "")

      _ ->
        "configured"
    end
  end
end
