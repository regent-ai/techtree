defmodule TechTree.IPFS.LighthouseClientTest do
  use ExUnit.Case, async: false

  alias TechTree.IPFS.LighthouseClient

  setup do
    previous = Application.get_env(:tech_tree, LighthouseClient)

    Application.put_env(:tech_tree, LighthouseClient,
      api_key: "test-key",
      base_url: "https://upload.test",
      gateway_base: "https://gateway.test/ipfs",
      storage_type: "annual",
      mock_uploads: true
    )

    on_exit(fn ->
      if previous do
        Application.put_env(:tech_tree, LighthouseClient, previous)
      else
        Application.delete_env(:tech_tree, LighthouseClient)
      end
    end)

    :ok
  end

  test "upload_content!/3 mock mode returns deterministic valid cid" do
    upload = LighthouseClient.upload_content!("notebook.py", "print('ok')", mock_uploads: true)

    assert upload.name == "notebook.py"
    assert upload.size == byte_size("print('ok')")
    assert LighthouseClient.valid_cid?(upload.cid)
    assert upload.gateway_url == "https://gateway.test/ipfs/#{upload.cid}"
  end

  test "upload_path!/2 mock mode uploads file content" do
    tmp_path =
      Path.join(System.tmp_dir!(), "lighthouse-client-#{System.unique_integer([:positive])}.txt")

    File.write!(tmp_path, "tmp-content")

    on_exit(fn -> File.rm(tmp_path) end)

    upload = LighthouseClient.upload_path!(tmp_path, mock_uploads: true)

    assert upload.name == Path.basename(tmp_path)
    assert upload.size == byte_size("tmp-content")
    assert LighthouseClient.valid_cid?(upload.cid)
  end

  test "decode_upload_response!/1 accepts nested data envelopes" do
    cid = "bafybeibwzifh6x6s6sa2r5y4d7zjz3mx2mhn7abm2wxyx7szj2z5g2rmcq"

    upload =
      LighthouseClient.decode_upload_response!(%{
        "data" => %{"Hash" => cid, "Name" => "manifest.json", "Size" => "128"}
      })

    assert upload.cid == cid
    assert upload.name == "manifest.json"
    assert upload.size == "128"
    assert upload.gateway_url == "https://gateway.test/ipfs/#{cid}"
  end

  test "decode_upload_response!/1 rejects invalid cids" do
    assert_raise RuntimeError, ~r/invalid CID/, fn ->
      LighthouseClient.decode_upload_response!(%{"Hash" => "not-a-cid", "Name" => "x"})
    end
  end
end