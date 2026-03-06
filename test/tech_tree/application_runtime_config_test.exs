defmodule TechTree.ApplicationRuntimeConfigTest do
  use ExUnit.Case, async: true

  describe "validate_siwa_runtime_config!/2" do
    test "allows skip_http_verify in test environment" do
      assert :ok =
               TechTree.Application.validate_siwa_runtime_config!(
                 :test,
                 skip_http_verify: true
               )
    end

    test "allows standard SIWA config in non-test environments" do
      assert :ok =
               TechTree.Application.validate_siwa_runtime_config!(
                 :prod,
                 internal_url: "http://siwa-sidecar:4100",
                 shared_secret: "secret"
               )
    end

    test "raises when skip_http_verify is enabled outside tests" do
      assert_raise RuntimeError,
                   ~r/skip_http_verify may only be enabled in :test/,
                   fn ->
                     TechTree.Application.validate_siwa_runtime_config!(
                       :dev,
                       skip_http_verify: true
                     )
                   end
    end

    test "raises when :siwa configuration is not a keyword list" do
      assert_raise ArgumentError,
                   ~r/expected :siwa to be a keyword list/,
                   fn ->
                     TechTree.Application.validate_siwa_runtime_config!(:test, %{
                       skip_http_verify: true
                     })
                   end
    end
  end
end
