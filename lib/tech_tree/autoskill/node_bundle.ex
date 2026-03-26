defmodule TechTree.Autoskill.NodeBundle do
  use TechTree.Schema

  @moduledoc """
  Multi-file bundle metadata for autoskill skill and eval versions.
  """

  schema "node_bundles" do
    field :bundle_type, Ecto.Enum, values: [:skill, :eval]
    field :access_mode, Ecto.Enum, values: [:public_free, :gated_paid]
    field :preview_md, :string
    field :bundle_manifest, :map
    field :primary_file, :string
    field :marimo_entrypoint, :string
    field :bundle_uri, :string
    field :bundle_cid, :string
    field :bundle_hash, :string
    field :encrypted_bundle_uri, :string
    field :encrypted_bundle_cid, :string
    field :encryption_meta, :map
    field :payment_rail, Ecto.Enum, values: [:x402, :mpp, :manual]
    field :access_policy, :map

    belongs_to :node, TechTree.Nodes.Node

    timestamps()
  end

  def changeset(bundle, attrs) do
    bundle
    |> cast(attrs, [
      :node_id,
      :bundle_type,
      :access_mode,
      :preview_md,
      :bundle_manifest,
      :primary_file,
      :marimo_entrypoint,
      :bundle_uri,
      :bundle_cid,
      :bundle_hash,
      :encrypted_bundle_uri,
      :encrypted_bundle_cid,
      :encryption_meta,
      :payment_rail,
      :access_policy
    ])
    |> validate_required([
      :node_id,
      :bundle_type,
      :access_mode,
      :bundle_manifest,
      :marimo_entrypoint
    ])
    |> validate_marimo_entrypoint()
    |> validate_bundle_version()
    |> validate_access_shape()
    |> foreign_key_constraint(:node_id)
    |> unique_constraint(:node_id)
  end

  defp validate_marimo_entrypoint(changeset) do
    case get_field(changeset, :marimo_entrypoint) do
      value when is_binary(value) ->
        if String.trim(value) == "" do
          add_error(changeset, :marimo_entrypoint, "must be present")
        else
          changeset
        end

      _ ->
        add_error(changeset, :marimo_entrypoint, "must be present")
    end
  end

  defp validate_bundle_version(changeset) do
    case get_field(changeset, :bundle_type) do
      :eval ->
        metadata =
          changeset
          |> get_field(:bundle_manifest, %{})
          |> case do
            %{"metadata" => manifest_metadata} when is_map(manifest_metadata) -> manifest_metadata
            %{metadata: manifest_metadata} when is_map(manifest_metadata) -> manifest_metadata
            _ -> %{}
          end

        case metadata["version"] || metadata[:version] do
          value when is_binary(value) ->
            if String.trim(value) == "" do
              add_error(changeset, :bundle_manifest, "eval bundles must declare metadata.version")
            else
              changeset
            end

          _ ->
            add_error(changeset, :bundle_manifest, "eval bundles must declare metadata.version")
        end

      _ ->
        changeset
    end
  end

  defp validate_access_shape(changeset) do
    case get_field(changeset, :access_mode) do
      :public_free ->
        validate_at_least_one_location(changeset, [:bundle_uri, :bundle_cid])

      :gated_paid ->
        changeset
        |> validate_required([:encrypted_bundle_uri, :payment_rail])
        |> validate_required([:access_policy])

      _ ->
        changeset
    end
  end

  defp validate_at_least_one_location(changeset, fields) do
    present? =
      Enum.any?(fields, fn field ->
        case get_field(changeset, field) do
          value when is_binary(value) -> String.trim(value) != ""
          _ -> false
        end
      end)

    if present?,
      do: changeset,
      else: add_error(changeset, :bundle_uri, "bundle location is required")
  end
end
