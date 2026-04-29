defmodule TechTree.IPFS.LighthouseClient do
  @moduledoc false

  @endpoint "/api/v0/add"
  @cid_v0_regex ~r/^Qm[1-9A-HJ-NP-Za-km-z]{44}$/
  @cid_v1_regex ~r/^b[a-z2-7]{20,}$/i
  @telemetry_event [:tech_tree, :ipfs, :lighthouse, :upload]

  defmodule UploadResult do
    @moduledoc false
    @enforce_keys [:cid, :name]
    defstruct [:cid, :name, :size, :gateway_url, :raw]

    @type t :: %__MODULE__{
            cid: String.t(),
            name: String.t(),
            size: String.t() | integer() | nil,
            gateway_url: String.t(),
            raw: map()
          }
  end

  @callback upload_content(String.t(), binary(), keyword()) ::
              {:ok, UploadResult.t()} | {:error, term()}
  @callback upload_path(String.t(), keyword()) :: {:ok, UploadResult.t()} | {:error, term()}

  @spec upload_content(String.t(), binary(), keyword()) ::
          {:ok, UploadResult.t()} | {:error, term()}
  def upload_content(filename, content, opts \\ [])
      when is_binary(filename) and is_binary(content) do
    case opts[:upload_fun] || Process.get({__MODULE__, :upload_fun}) do
      upload_fun when is_function(upload_fun, 3) ->
        call_upload_fun(upload_fun, filename, content, opts)

      _ ->
        content_type =
          opts[:content_type] || MIME.from_path(filename) || "application/octet-stream"

        mock_uploads = opts[:mock_uploads] || config!(:mock_uploads)

        if mock_uploads do
          {:ok, mock_upload_result(filename, content)}
        else
          perform_upload(
            filename,
            {content, filename: filename, content_type: content_type},
            opts
          )
        end
    end
  end

  @spec upload_path(String.t(), keyword()) :: {:ok, UploadResult.t()} | {:error, term()}
  def upload_path(path, opts \\ []) when is_binary(path) do
    filename = opts[:filename] || Path.basename(path)
    content_type = opts[:content_type] || MIME.from_path(path) || "application/octet-stream"

    case opts[:upload_fun] || Process.get({__MODULE__, :upload_fun}) do
      upload_fun when is_function(upload_fun, 3) ->
        with {:ok, content} <- File.read(path) do
          call_upload_fun(
            upload_fun,
            filename,
            content,
            Keyword.put(opts, :content_type, content_type)
          )
        end

      _ ->
        mock_uploads = opts[:mock_uploads] || config!(:mock_uploads)

        if mock_uploads do
          with {:ok, content} <- File.read(path) do
            upload_content(filename, content, Keyword.put(opts, :content_type, content_type))
          end
        else
          with {:ok, stat} <- File.stat(path) do
            perform_upload(
              filename,
              {File.stream!(path, [], 64_000),
               filename: filename, content_type: content_type, size: stat.size},
              opts
            )
          end
        end
    end
  end

  @spec gateway_url(String.t()) :: String.t()
  def gateway_url(cid), do: "#{config!(:gateway_base)}/#{cid}"

  @spec valid_cid?(term()) :: boolean()
  def valid_cid?(cid) when is_binary(cid) do
    String.match?(cid, @cid_v0_regex) or String.match?(cid, @cid_v1_regex)
  end

  def valid_cid?(_cid), do: false

  @spec decode_upload_response(map() | String.t()) :: {:ok, UploadResult.t()} | {:error, term()}
  def decode_upload_response(body) when is_binary(body) do
    with {:ok, decoded} <- Jason.decode(body) do
      decode_upload_response(decoded)
    else
      {:error, reason} -> {:error, {:invalid_json, reason}}
    end
  end

  def decode_upload_response(body) when is_map(body) do
    data = if is_map(body["data"]), do: body["data"], else: body

    with cid when is_binary(cid) <- data["Hash"] || data["hash"],
         true <- valid_cid?(cid) do
      name = data["Name"] || data["name"] || ""
      size = data["Size"] || data["size"]

      {:ok,
       %UploadResult{
         cid: cid,
         name: name,
         size: size,
         gateway_url: gateway_url(cid),
         raw: body
       }}
    else
      nil -> {:error, :missing_cid}
      false -> {:error, :invalid_cid}
    end
  end

  @spec mock_upload_result(String.t(), binary()) :: UploadResult.t()
  defp mock_upload_result(filename, content) do
    digest =
      :crypto.hash(:sha256, [filename, ":", content])
      |> Base.encode32(case: :lower, padding: false)

    cid = "b#{String.slice(digest, 0, 58)}"

    %UploadResult{
      cid: cid,
      name: filename,
      size: byte_size(content),
      gateway_url: gateway_url(cid),
      raw: %{"mock" => true, "Hash" => cid, "Name" => filename, "Size" => byte_size(content)}
    }
  end

  @spec perform_upload(String.t(), tuple(), keyword()) ::
          {:ok, UploadResult.t()} | {:error, term()}
  defp perform_upload(filename, multipart_file, opts) do
    storage_type = opts[:storage_type] || config!(:storage_type)
    started_at = System.monotonic_time()

    try do
      result =
        Req.post(
          url: "#{config!(:base_url)}#{@endpoint}",
          headers: [
            {"authorization", "Bearer #{config!(:api_key)}"},
            {"x-storage-type", storage_type}
          ],
          form_multipart: [file: multipart_file],
          receive_timeout: opts[:receive_timeout] || 120_000,
          connect_options: [timeout: opts[:connect_timeout] || 5_000]
        )

      decoded =
        with {:ok, %{status: status, body: body}} when status in 200..299 <- result,
             {:ok, %UploadResult{} = upload} <- decode_upload_response(body) do
          upload = if upload.name == "", do: %UploadResult{upload | name: filename}, else: upload
          {:ok, upload}
        else
          {:ok, %{status: status}} -> {:error, {:http_status, status}}
          {:error, reason} -> {:error, reason}
        end

      emit_upload_telemetry(decoded, started_at, filename, storage_type)
      decoded
    rescue
      error ->
        result = {:error, error}
        emit_upload_telemetry(result, started_at, filename, storage_type)
        result
    end
  end

  defp call_upload_fun(upload_fun, filename, content, opts) do
    case upload_fun.(filename, content, opts) do
      {:ok, %UploadResult{} = upload} -> {:ok, upload}
      %UploadResult{} = upload -> {:ok, upload}
      {:error, reason} -> {:error, reason}
      other -> {:error, {:invalid_upload_result, other}}
    end
  rescue
    error -> {:error, error}
  end

  defp emit_upload_telemetry(result, started_at, filename, storage_type) do
    duration = System.monotonic_time() - started_at
    outcome = if match?({:ok, _upload}, result), do: "ok", else: "error"

    :telemetry.execute(
      @telemetry_event,
      %{duration: duration},
      %{filename: filename, storage_type: storage_type, outcome: outcome}
    )
  end

  @spec config!(atom()) :: term()
  defp config!(key) do
    Application.fetch_env!(:tech_tree, __MODULE__) |> Keyword.fetch!(key)
  end
end
