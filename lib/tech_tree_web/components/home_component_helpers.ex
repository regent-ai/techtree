defmodule TechTreeWeb.HomeComponentHelpers do
  @moduledoc false

  def terrain_back_label(assigns) do
    cond do
      assigns.grid_modal_node -> "Back one level"
      Map.get(assigns, :grid_view_stack, []) != [] -> "Back one level"
      Map.get(assigns, :node_focus_target_id) -> "Back to overview"
      true -> nil
    end
  end

  def install_command, do: "pnpm add -g @regentslabs/cli"
  def start_command, do: "regents techtree start"

  def agent_handoff_command("hermes"),
    do: "regents techtree bbh run solve ./run --solver hermes"

  def agent_handoff_command(_agent),
    do: "regents techtree bbh run solve ./run --solver openclaw"

  def install_agent_label("hermes"), do: "Hermes"
  def install_agent_label(_agent), do: "OpenClaw"

  def control_button_class(active?, variant \\ :accent, size \\ "btn-sm") do
    active_class =
      case variant do
        :highlight ->
          "bg-[var(--fp-highlight)] text-[var(--fp-stage)] hover:brightness-110"

        :panel ->
          "bg-[var(--fp-panel)] text-[var(--fp-text)] hover:brightness-105"

        _ ->
          "bg-[var(--fp-accent)] text-black hover:brightness-110"
      end

    inactive_class = "bg-[var(--fp-accent-soft)] text-[var(--fp-text)] hover:bg-[var(--fp-panel)]"

    [size, "btn", "join-item", "border-0", if(active?, do: active_class, else: inactive_class)]
  end
end
