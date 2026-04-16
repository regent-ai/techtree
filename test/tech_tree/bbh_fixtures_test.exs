defmodule TechTree.BBHFixturesTest do
  use TechTree.DataCase, async: true

  alias TechTree.BBHFixtures

  test "insert_genome! reuses the same genome when the canonical bundle matches" do
    first =
      BBHFixtures.insert_genome!(%{
        genome_id: "genome-alpha",
        label: "Genome Alpha",
        model_id: "gpt-same",
        harness_type: "hermes"
      })

    second =
      BBHFixtures.insert_genome!(%{
        genome_id: "genome-alpha",
        label: "Genome Alpha",
        model_id: "gpt-same",
        harness_type: "hermes"
      })

    assert second.genome_id == first.genome_id
    assert second.normalized_bundle_hash == first.normalized_bundle_hash
  end

  test "insert_genome! raises when the canonical bundle matches but display fields conflict" do
    _genome =
      BBHFixtures.insert_genome!(%{
        genome_id: "genome-alpha",
        label: "Genome Alpha",
        model_id: "gpt-same",
        harness_type: "hermes"
      })

    assert_raise RuntimeError, ~r/conflicting genome fixture/, fn ->
      BBHFixtures.insert_genome!(%{
        genome_id: "genome-beta",
        label: "Genome Beta",
        model_id: "gpt-same",
        harness_type: "hermes"
      })
    end
  end
end
