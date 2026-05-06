defmodule TechTreeWeb.HumanComponents do
  @moduledoc false
  use TechTreeWeb, :html

  attr :kicker, :string, required: true
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  slot :actions

  def human_header(assigns) do
    ~H"""
    <header class="hu-header" data-motion="reveal">
      <div>
        <p class="hu-kicker"><span class="tt-public-sigil" aria-hidden="true">⩛</span> {@kicker}</p>
        <h1 class="hu-title">{@title}</h1>
        <p :if={@subtitle} class="hu-subtitle">{@subtitle}</p>
      </div>

      <div :if={@actions != []} class="hu-header-actions">
        {render_slot(@actions)}
      </div>
    </header>
    """
  end

  attr :title, :string, required: true
  attr :id, :string, default: nil
  slot :inner_block, required: true

  def human_section(assigns) do
    ~H"""
    <section id={@id} class="hu-section" data-motion="reveal">
      <h2 class="hu-section-title">{@title}</h2>
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  def human_stat(assigns) do
    ~H"""
    <div class="hu-stat">
      <dt class="hu-stat-label">{@label}</dt>
      <dd class="hu-stat-value">{@value}</dd>
    </div>
    """
  end

  attr :message, :string, required: true

  def empty_state(assigns) do
    ~H"""
    <div class="hu-empty">{@message}</div>
    """
  end

  @spec toggle_class(boolean()) :: String.t()
  def toggle_class(true), do: "hu-toggle-link hu-toggle-active"
  def toggle_class(false), do: "hu-toggle-link"

  @spec kind(atom() | String.t() | term()) :: String.t()
  def kind(value) when is_atom(value), do: value |> Atom.to_string() |> String.replace("_", " ")
  def kind(value) when is_binary(value), do: value
  def kind(_value), do: "node"

  @spec present(term(), String.t()) :: String.t()
  def present(value, fallback)

  def present(value, fallback) when is_binary(value) do
    case String.trim(value) do
      "" -> fallback
      trimmed -> trimmed
    end
  end

  def present(_value, fallback), do: fallback

  @spec autoskill?(map()) :: boolean()
  def autoskill?(%{autoskill: autoskill}) when is_map(autoskill), do: true
  def autoskill?(_node), do: false

  @spec autoskill_mode_label(map()) :: String.t() | nil
  def autoskill_mode_label(%{autoskill: %{access_mode: mode}}) when is_binary(mode) do
    case mode do
      "gated_paid" -> "Gated paid"
      "public_free" -> "Public free"
      _ -> nil
    end
  end

  def autoskill_mode_label(_node), do: nil

  @spec autoskill_flavor_label(map()) :: String.t() | nil
  def autoskill_flavor_label(%{autoskill: %{flavor: flavor}}) when is_binary(flavor) do
    case flavor do
      "eval" -> "Eval scenario"
      "skill" -> "Autoskill"
      _ -> nil
    end
  end

  def autoskill_flavor_label(_node), do: nil

  @spec autoskill_score_summary(map()) :: String.t() | nil
  def autoskill_score_summary(%{autoskill: %{scorecard: scorecard}}) when is_map(scorecard) do
    replicable = Map.get(scorecard, :replicable, Map.get(scorecard, "replicable", %{}))

    unique_agents =
      Map.get(replicable, :unique_agent_count, Map.get(replicable, "unique_agent_count", 0))

    median_score = Map.get(replicable, :median_score, Map.get(replicable, "median_score"))

    cond do
      is_number(median_score) ->
        "#{Float.round(median_score, 2)} median from #{unique_agents} replicable reviews"

      unique_agents > 0 ->
        "#{unique_agents} replicable reviews"

      true ->
        nil
    end
  end

  def autoskill_score_summary(_node), do: nil

  @spec autoskill_listing_summary(map()) :: String.t() | nil
  def autoskill_listing_summary(%{autoskill: %{listing: listing}}) when is_map(listing) do
    status = Map.get(listing, :status, Map.get(listing, "status"))
    price = Map.get(listing, :price_usdc, Map.get(listing, "price_usdc"))

    cond do
      is_binary(status) and not is_nil(price) -> "#{status} at #{price} USDC"
      is_binary(status) -> status
      true -> nil
    end
  end

  def autoskill_listing_summary(_node), do: nil
end
