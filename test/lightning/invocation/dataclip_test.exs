defmodule Lightning.Invocation.DataclipTest do
  use Lightning.DataCase, async: true

  alias Lightning.Invocation.Dataclip

  import Lightning.Factories

  describe "no type provided" do
    test "does not break request validation" do
      changeset =
        params_with_assocs(:dataclip, type: "")
        |> Dataclip.new()

      assert changeset.valid?
    end
  end

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

    test "is valid when request is set to nil" do
      assert {:ok, _dataclip} =
        params_with_assocs(:dataclip, request: nil)
        |> Dataclip.new()
        |> Repo.insert()
    end

    test "is valid when request is set absent" do
      assert {:ok, _dataclip} =
        params_with_assocs(:dataclip)
        |> Dataclip.new()
        |> Repo.insert()
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

  describe "kafka dataclip" do
    test "can provide a request map" do
      {:ok, dataclip} =
        params_with_assocs(
          :dataclip,
          request: %{"partition" => 3},
          type: :kafka
        )
        |> Dataclip.new()
        |> Repo.insert()

      dataclip = dataclip |> Repo.reload()
      assert dataclip.request == nil, "Does not load request in query by default"

      request =
        Dataclip
        |> select([d], d.request)
        |> where([d], d.id == ^dataclip.id)
        |> Repo.one()

      assert request == %{"partition" => 3}
    end

    test "is invalid when request is set to nil" do
      changeset =
        params_with_assocs(:dataclip, type: :kafka, request: nil)
        |> Dataclip.new()

      refute changeset.valid?
      assert {:request, {"must be set for kafka type", []}} in changeset.errors
    end

    test "is invalid when request is absent" do
      changeset =
        params_with_assocs(:dataclip, type: :kafka)
        |> Dataclip.new()

      refute changeset.valid?
      assert {:request, {"must be set for kafka type", []}} in changeset.errors
    end
  end
end
