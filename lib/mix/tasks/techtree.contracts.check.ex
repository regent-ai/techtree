defmodule Mix.Tasks.Techtree.Contracts.Check do
  @moduledoc false
  use Mix.Task

  @shortdoc "Checks Techtree OpenAPI/router drift"
  @http_verbs ~w(get post put patch delete)
  @contract_path "docs/api-contract.openapiv3.yaml"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("compile")

    contract_routes = contract_routes!(@contract_path)
    router_routes = router_routes!()

    missing_in_router = MapSet.difference(contract_routes, router_routes)
    missing_in_contract = MapSet.difference(router_routes, contract_routes)

    if MapSet.size(missing_in_router) == 0 and MapSet.size(missing_in_contract) == 0 do
      Mix.shell().info("OpenAPI/router contract check passed")
    else
      report_drift("OpenAPI routes missing in Phoenix router", missing_in_router)
      report_drift("Phoenix router routes missing in OpenAPI", missing_in_contract)
      Mix.raise("OpenAPI/router contract drift detected")
    end
  end

  def contract_routes!(path) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.reduce({nil, MapSet.new()}, fn line, {current_path, routes} ->
      cond do
        path = openapi_path(line) ->
          {path, routes}

        verb = openapi_verb(line) ->
          {current_path, add_route(routes, verb, current_path)}

        true ->
          {current_path, routes}
      end
    end)
    |> elem(1)
    |> MapSet.filter(&owned_route?/1)
  end

  def router_routes! do
    TechTreeWeb.Router.__routes__()
    |> Enum.reduce(MapSet.new(), fn route, routes ->
      route_path = normalize_router_path(route.path)
      add_route(routes, String.downcase(to_string(route.verb)), route_path)
    end)
    |> MapSet.filter(&owned_route?/1)
  end

  defp add_route(routes, verb, path) when verb in @http_verbs and is_binary(path) do
    MapSet.put(routes, {String.upcase(verb), path})
  end

  defp add_route(routes, _verb, _path), do: routes

  defp openapi_path(line) do
    case Regex.run(~r/^  (\/[^:]+):\s*$/, line) do
      [_, path] -> path
      _ -> nil
    end
  end

  defp openapi_verb(line) do
    case Regex.run(~r/^    (get|post|put|patch|delete):\s*$/, line) do
      [_, verb] -> verb
      _ -> nil
    end
  end

  defp normalize_router_path(path) do
    Regex.replace(~r/:([A-Za-z_][A-Za-z0-9_]*)/, path, "{\\1}")
  end

  defp owned_route?({_verb, path}) do
    cond do
      path == "/health" -> true
      String.starts_with?(path, "/api/auth/") -> true
      String.starts_with?(path, "/auth/orcid/") -> true
      String.starts_with?(path, "/api/internal/") -> true
      String.starts_with?(path, "/api/platform/") -> true
      String.starts_with?(path, "/v1/") -> true
      true -> false
    end
  end

  defp report_drift(title, routes) do
    if MapSet.size(routes) == 0, do: :ok, else: do_report_drift(title, routes)
  end

  defp do_report_drift(title, routes) do
    Mix.shell().error(title <> ":")

    routes
    |> Enum.sort()
    |> Enum.each(fn {verb, path} -> Mix.shell().error("  #{verb} #{path}") end)
  end
end
