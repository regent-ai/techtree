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
        <p class="hu-kicker">{@kicker}</p>
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
end
