defmodule TechTree.IPFS.LighthouseClient do
  @moduledoc false

  @endpoint "/api/v0/add"

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
  def upload_content!(filename, content, opts \\ []) when is_binary(filename) and is_binary(content) do
    content_type = opts[:content_type] || MIME.from_path(filename) || "application/octet-stream"

    multipart =
      {:multipart,
       [
         {"file", content,
          filename: filename,
          headers: [{"content-type", content_type}]}
       ]}

    storage_type = opts[:storage_type] || config!(:storage_type)

    response =
      Req.post!(
        url: "#{config!(:base_url)}#{@endpoint}",
        headers: [
          {"authorization", "Bearer #{config!(:api_key)}"},
          {"x-storage-type", storage_type}
        ],
        body: multipart,
        receive_timeout: opts[:receive_timeout] || 120_000
      )

    decode_upload_response!(response.body)
  end

  @spec upload_path!(String.t(), keyword()) :: UploadResult.t()
  def upload_path!(path, opts \\ []) when is_binary(path) do
    filename = opts[:filename] || Path.basename(path)
    content_type = opts[:content_type] || MIME.from_path(path) || "application/octet-stream"
    content = File.read!(path)

    upload_content!(filename, content, Keyword.put(opts, :content_type, content_type))
  end

  @spec gateway_url(String.t()) :: String.t()
  def gateway_url(cid), do: "#{config!(:gateway_base)}/#{cid}"

  @spec decode_upload_response!(map() | String.t()) :: UploadResult.t()
  defp decode_upload_response!(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> decode_upload_response!(decoded)
      {:error, reason} -> raise "Lighthouse upload JSON decode failed: #{inspect(reason)} body=#{inspect(body)}"
    end
  end

  defp decode_upload_response!(body) when is_map(body) do
    data = if is_map(body["data"]), do: body["data"], else: body

    cid = data["Hash"] || data["hash"] || raise "Lighthouse response missing Hash: #{inspect(body)}"
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

  @spec config!(atom()) :: term()
  defp config!(key) do
    Application.fetch_env!(:tech_tree, __MODULE__) |> Keyword.fetch!(key)
  end
end
