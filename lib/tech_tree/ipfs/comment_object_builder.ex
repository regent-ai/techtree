defmodule TechTree.IPFS.CommentObjectBuilder do
  @moduledoc false

  alias TechTree.IPFS.{Digests, LighthouseClient}
  alias TechTree.Repo
  alias TechTree.Comments.Comment

  @spec build_and_pin!(Comment.t()) :: map()
  def build_and_pin!(%Comment{} = comment) do
    comment = Repo.preload(comment, [:author_agent])

    body =
      %{
        "version" => "techtree-comment@1",
        "comment_id" => comment.id,
        "node_id" => comment.node_id,
        "author" => %{
          "type" => "agent",
          "chain_id" => comment.author_agent.chain_id,
          "registry_address" => comment.author_agent.registry_address,
          "token_id" => decimal_to_string(comment.author_agent.token_id),
          "wallet_address" => comment.author_agent.wallet_address
        },
        "body_markdown" => comment.body_markdown,
        "body_plaintext" => comment.body_plaintext,
        "created_at" => DateTime.to_iso8601(comment.inserted_at || DateTime.utc_now())
      }
      |> Jason.encode_to_iodata!(pretty: true)
      |> IO.iodata_to_binary()

    hash_bin = Digests.sha256(body)
    hash_hex = Base.encode16(hash_bin, case: :lower)

    upload =
      LighthouseClient.upload_content!(
        "comment-#{comment.id}.json",
        body,
        content_type: "application/json"
      )

    %{
      cid: upload.cid,
      uri: "ipfs://#{upload.cid}",
      json: body,
      sha256_bin: hash_bin,
      sha256_hex: hash_hex
    }
  end

  @spec decimal_to_string(Decimal.t() | term()) :: String.t()
  defp decimal_to_string(%Decimal{} = decimal), do: Decimal.to_string(decimal, :normal)
  defp decimal_to_string(other), do: to_string(other)
end
