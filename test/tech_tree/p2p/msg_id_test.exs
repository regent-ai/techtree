defmodule TechTree.P2P.MsgIdTest do
  use ExUnit.Case, async: true

  alias TechTree.P2P.MsgId

  test "extracts transport_msg_id from valid json payloads" do
    payload = Jason.encode!(%{"transport_msg_id" => "trollbox:test:123", "body" => "hello"})

    assert MsgId.from_topic_and_data("regent.test.trollbox.global", payload) ==
             "trollbox:test:123"
  end

  test "falls back to a stable sha256 for invalid or missing ids" do
    topic = "regent.test.trollbox.global"
    payload = Jason.encode!(%{"body" => "hello"})

    assert MsgId.from_topic_and_data(topic, payload) ==
             :crypto.hash(:sha256, topic <> <<0>> <> payload)
  end
end
