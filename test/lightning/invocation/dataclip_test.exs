defmodule Lightning.Invocation.DataclipTest do
  use Lightning.DataCase, async: true

  alias Lightning.Invocation.Dataclip

  import Lightning.Factories

  describe "http_request" do
    test "can provide a request map" do
      {:ok, dataclip} =
        params_with_assocs(:dataclip, request: %{"url" => "https://example.com"})
        |> Dataclip.new()
        |> Repo.insert()

      dataclip = dataclip |> Repo.reload()
      assert dataclip.request == nil, "Does not load request in query by default"

      request =
        Dataclip
        |> select([d], d.request)
        |> where([d], d.id == ^dataclip.id)
        |> Repo.one()

      assert request == %{"url" => "https://example.com"}
    end

    test "only http_request dataclips can have a request" do
      changeset =
        params_with_assocs(:dataclip,
          request: %{"url" => "https://example.com"},
          type: :step_result
        )
        |> Dataclip.new()

      refute changeset.valid?
      assert {:request, {"cannot be set for this type", []}} in changeset.errors
    end
  end
end
