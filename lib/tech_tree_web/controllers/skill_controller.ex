defmodule TechTreeWeb.SkillController do
  use TechTreeWeb, :controller

  alias TechTree.IPFS.Digests
  alias TechTree.Nodes

  @semver_core_regex ~r/^[0-9]+\.[0-9]+\.[0-9]+$/

  @spec show_version(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show_version(conn, %{"slug" => slug, "version" => version}) do
    with {:ok, normalized_slug} <- normalize_slug(slug),
         {:ok, normalized_version} <- normalize_version(version),
         %{} = skill <- Nodes.get_skill_by_slug_and_version(normalized_slug, normalized_version) do
      render_skill(conn, skill)
    else
      _reason -> send_resp(conn, :not_found, "")
    end
  end

  @spec show_latest(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show_latest(conn, %{"slug" => slug}) do
    with {:ok, normalized_slug} <- normalize_slug(slug),
         %{} = skill <- Nodes.get_latest_skill(normalized_slug) do
      render_skill(conn, skill)
    else
      _reason -> send_resp(conn, :not_found, "")
    end
  end

  @spec show_raw(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show_raw(conn, %{"slug" => slug}) do
    show_latest(conn, %{"slug" => slug})
  end

  @spec render_skill(Plug.Conn.t(), map()) :: Plug.Conn.t()
  defp render_skill(conn, skill) do
    etag = skill_etag(skill)

    conn
    |> put_resp_content_type("text/markdown")
    |> put_resp_header("cache-control", "public, max-age=0, must-revalidate")
    |> put_resp_header("etag", etag)
    |> maybe_send_not_modified(etag, skill.skill_md_body)
  end

  @spec maybe_send_not_modified(Plug.Conn.t(), String.t(), String.t()) :: Plug.Conn.t()
  defp maybe_send_not_modified(conn, etag, body) do
    if etag_matches?(conn, etag) do
      send_resp(conn, :not_modified, "")
    else
      send_resp(conn, :ok, body)
    end
  end

  @spec etag_matches?(Plug.Conn.t(), String.t()) :: boolean()
  defp etag_matches?(conn, etag) do
    conn
    |> get_req_header("if-none-match")
    |> Enum.any?(fn header ->
      header
      |> String.split(",", trim: true)
      |> Enum.any?(fn candidate ->
        trimmed = String.trim(candidate)
        trimmed == "*" or trimmed == etag
      end)
    end)
  end

  @spec skill_etag(map()) :: String.t()
  defp skill_etag(skill) do
    digest_source =
      case normalize_text(skill.skill_md_cid) do
        nil -> Digests.sha256_hex(skill.skill_md_body)
        cid -> cid
      end

    ~s("#{digest_source}")
  end

  @spec normalize_slug(term()) :: {:ok, String.t()} | {:error, :invalid_slug}
  defp normalize_slug(slug) when is_binary(slug) do
    case String.trim(slug) do
      "" -> {:error, :invalid_slug}
      normalized -> {:ok, normalized}
    end
  end

  defp normalize_slug(_slug), do: {:error, :invalid_slug}

  @spec normalize_version(term()) :: {:ok, String.t()} | {:error, :invalid_version}
  defp normalize_version(version) when is_binary(version) do
    normalized = String.trim(version)

    if String.match?(normalized, @semver_core_regex) do
      {:ok, normalized}
    else
      {:error, :invalid_version}
    end
  end

  defp normalize_version(_version), do: {:error, :invalid_version}

  @spec normalize_text(term()) :: String.t() | nil
  defp normalize_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_text(_value), do: nil
end
