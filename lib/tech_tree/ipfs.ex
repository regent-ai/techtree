defmodule TechTree.IPFS do
  @moduledoc false

  alias TechTree.IPFS.{NodeBundleBuilder, CommentObjectBuilder}

  @spec build_and_pin_node_bundle(TechTree.Nodes.Node.t(), String.t(), String.t() | nil, list(map())) ::
          {:ok, map()} | {:error, term()}
  def build_and_pin_node_bundle(node, notebook_source, skill_md_body \\ nil, sidelinks \\ []) do
    {:ok,
     NodeBundleBuilder.build_and_pin!(
       node,
       %{
         "notebook_source" => notebook_source,
         "skill_md_body" => skill_md_body,
         "sidelinks" => sidelinks
       }
     )}
  rescue
    error -> {:error, error}
  end

  @spec build_and_pin_comment(TechTree.Comments.Comment.t()) :: {:ok, map()} | {:error, term()}
  def build_and_pin_comment(comment) do
    {:ok, CommentObjectBuilder.build_and_pin!(comment)}
  rescue
    error -> {:error, error}
  end

  @spec verify_recent_cids!() :: :ok
  def verify_recent_cids!, do: :ok
end
