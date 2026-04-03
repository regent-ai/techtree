defmodule TechTree.IPFS.LighthouseClient do
  @moduledoc false

  @endpoint "/api/v0/add"
  @cid_v0_regex ~r/^Qm[1-9A-HJ-NP-Za-km-z]{44}$/
  @cid_v1_regex ~r/^b[a-z2-7]{20,}$/i

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

  @spec upload_content!(String.t(), binary(), keyword()) :: UploadResult.t()
  def upload_content!(filename, content, opts \\ [])
      when is_binary(filename) and is_binary(content) do
    case opts[:upload_fun] || Process.get({__MODULE__, :upload_fun}) do
      upload_fun when is_function(upload_fun, 3) ->
        upload_fun.(filename, content, opts)

      _ ->
        content_type =
          opts[:content_type] || MIME.from_path(filename) || "application/octet-stream"

        mock_uploads = opts[:mock_uploads] || config!(:mock_uploads)

        if mock_uploads do
          mock_upload_result(filename, content)
        else
          perform_upload!(
            filename,
            {content, filename: filename, content_type: content_type},
            opts
          )
        end
    end
  end

  @spec upload_path!(String.t(), keyword()) :: UploadResult.t()
  def upload_path!(path, opts \\ []) when is_binary(path) do
    filename = opts[:filename] || Path.basename(path)
    content_type = opts[:content_type] || MIME.from_path(path) || "application/octet-stream"

    case opts[:upload_fun] || Process.get({__MODULE__, :upload_fun}) do
      upload_fun when is_function(upload_fun, 3) ->
        content = File.read!(path)
        upload_fun.(filename, content, Keyword.put(opts, :content_type, content_type))

      _ ->
        mock_uploads = opts[:mock_uploads] || config!(:mock_uploads)

        if mock_uploads do
          content = File.read!(path)
          upload_content!(filename, content, Keyword.put(opts, :content_type, content_type))
        else
          size = File.stat!(path).size

          perform_upload!(
            filename,
            {File.stream!(path, [], 64_000),
             filename: filename, content_type: content_type, size: size},
            opts
          )
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

  @spec decode_upload_response!(map() | String.t()) :: UploadResult.t()
  def decode_upload_response!(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} ->
        decode_upload_response!(decoded)

      {:error, reason} ->
        raise "Lighthouse upload JSON decode failed: #{inspect(reason)} body=#{inspect(body)}"
    end
  end

  def decode_upload_response!(body) when is_map(body) do
    data = if is_map(body["data"]), do: body["data"], else: body

    cid =
      data["Hash"] || data["hash"] || raise "Lighthouse response missing Hash: #{inspect(body)}"

    unless valid_cid?(cid) do
      raise "Lighthouse response returned invalid CID: #{inspect(cid)} body=#{inspect(body)}"
    end

    name = data["Name"] || data["name"] || ""
    size = data["Size"] || data["size"]

    %UploadResult{
      cid: cid,
      name: name,
      size: size,
      gateway_url: gateway_url(cid),
      raw: body
    }
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

  @spec perform_upload!(String.t(), tuple(), keyword()) :: UploadResult.t()
  defp perform_upload!(filename, multipart_file, opts) do
    storage_type = opts[:storage_type] || config!(:storage_type)

    response =
      Req.post!(
        url: "#{config!(:base_url)}#{@endpoint}",
        headers: [
          {"authorization", "Bearer #{config!(:api_key)}"},
          {"x-storage-type", storage_type}
        ],
        form_multipart: [file: multipart_file],
        receive_timeout: opts[:receive_timeout] || 120_000
      )

    case decode_upload_response!(response.body) do
      %UploadResult{name: ""} = upload -> %UploadResult{upload | name: filename}
      upload -> upload
    end
  end

  @spec config!(atom()) :: term()
  defp config!(key) do
    Application.fetch_env!(:tech_tree, __MODULE__) |> Keyword.fetch!(key)
  end
end
