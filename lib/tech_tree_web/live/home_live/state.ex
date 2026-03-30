defmodule TechTreeWeb.HomeLive.State do
  @moduledoc false

  alias TechTreeWeb.HomePresenter

  def toggle_panel("top", assigns), do: %{top_section_open?: !Map.get(assigns, :top_section_open?, true)}
  def toggle_panel("agent", assigns), do: %{agent_panel_open?: !Map.get(assigns, :agent_panel_open?, true)}
  def toggle_panel("human", assigns), do: %{human_panel_open?: !Map.get(assigns, :human_panel_open?, true)}
  def toggle_panel(_panel, _assigns), do: %{}

  def next_view_mode(mode, _current_mode) when mode in ["graph", "grid"], do: mode
  def next_view_mode(_mode, current_mode), do: current_mode

  def select_node(node_id, graph_nodes, fallback_node_id) do
    selected_node_id = parse_optional_integer(node_id) || fallback_node_id

    %{
      selected_node_id: selected_node_id,
      selected_node: selected_node(graph_nodes, selected_node_id)
    }
  end

  def focus_agent(agent_id_param, current_agent_id, agent_focus_options) do
    next_agent_id =
      agent_id_param
      |> parse_optional_integer()
      |> toggle_integer_focus(current_agent_id)

    next_query = HomePresenter.focus_agent_input(agent_focus_options, next_agent_id)

    %{
      selected_agent_id: next_agent_id,
      graph_agent_query: next_query,
      graph_agent_matches:
        HomePresenter.matching_agent_focus_options(agent_focus_options, next_query)
    }
  end

  def update_agent_query(query, agent_focus_options) do
    %{
      graph_agent_query: query,
      graph_agent_matches:
        HomePresenter.matching_agent_focus_options(agent_focus_options, query)
    }
  end

  def focus_agent_query(query, agent_focus_options) do
    next_agent_id =
      agent_focus_options
      |> HomePresenter.resolve_agent_focus(query)
      |> case do
        nil -> nil
        option -> option.id
      end

    %{
      graph_agent_query: query,
      graph_agent_matches:
        HomePresenter.matching_agent_focus_options(agent_focus_options, query),
      selected_agent_id: next_agent_id
    }
  end

  def focus_subtree(params, current_selected_node_id, current_root_id, current_mode) do
    subtree_mode =
      case Map.get(params, "mode") do
        "children" -> "children"
        "descendants" -> "descendants"
        _ -> nil
      end

    subtree_root_id =
      params
      |> Map.get("node_id")
      |> parse_optional_integer()
      |> case do
        nil -> current_selected_node_id
        parsed -> parsed
      end

    {next_root_id, next_mode} =
      cond do
        is_nil(subtree_mode) or is_nil(subtree_root_id) ->
          {nil, nil}

        current_root_id == subtree_root_id and current_mode == subtree_mode ->
          {nil, nil}

        true ->
          {subtree_root_id, subtree_mode}
      end

    %{subtree_root_id: next_root_id, subtree_mode: next_mode}
  end

  def toggle_show_null_results(assigns) do
    %{show_null_results?: !Map.get(assigns, :show_null_results?, false)}
  end

  def toggle_filter_null_results(assigns) do
    next_value = !Map.get(assigns, :filter_to_null_results?, false)

    %{
      filter_to_null_results?: next_value,
      show_null_results?: if(next_value, do: true, else: Map.get(assigns, :show_null_results?, false))
    }
  end

  def clear_graph_focus(agent_focus_options) do
    %{
      selected_agent_id: nil,
      subtree_root_id: nil,
      subtree_mode: nil,
      show_null_results?: false,
      filter_to_null_results?: false,
      graph_agent_query: "",
      graph_agent_matches:
        HomePresenter.matching_agent_focus_options(agent_focus_options, "")
    }
  end

  def parse_optional_integer(nil), do: nil

  def parse_optional_integer(value) do
    case Integer.parse(to_string(value)) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  def toggle_integer_focus(value, current) when value == current, do: nil
  def toggle_integer_focus(value, _current), do: value

  def selected_node(graph_nodes, selected_node_id) do
    Enum.find(graph_nodes, &(&1.id == selected_node_id))
  end
end
