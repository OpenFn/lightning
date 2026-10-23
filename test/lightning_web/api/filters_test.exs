defmodule LightningWeb.API.FiltersTest do
  use ExUnit.Case, async: true

  alias LightningWeb.API.Errors
  alias LightningWeb.API.Filters

  describe "runs/1" do
    test "answers the filters it accepts, parsed" do
      assert Filters.runs(%{
               "inserted_before" => "2024-01-01T02:00:00+02:00",
               "state" => "started,failed",
               "page" => "2"
             }) ==
               {:ok,
                %{
                  inserted_before: ~U[2024-01-01 00:00:00.000000Z],
                  state: ["started", "failed"]
                }}
    end
  end

  describe "datetime parameters" do
    test "a value that is not a datetime is refused, whatever it looks like" do
      for {filter, parameters} <- [
            {&Filters.runs/1,
             ~w(inserted_after inserted_before updated_after updated_before)},
            {&Filters.work_orders/1,
             ~w(inserted_after inserted_before updated_after updated_before)},
            {&Filters.log_lines/1, ~w(timestamp_after timestamp_before)}
          ],
          parameter <- parameters,
          value <- ["not-a-valid-datetime", "2024-13-45", "123456"] do
        assert {:error, changeset} = filter.(%{parameter => value})

        assert Errors.parameters(changeset).errors == [
                 %{parameter: parameter, code: :type, detail: "is invalid"}
               ],
               "#{parameter}=#{value}"
      end
    end
  end

  describe "runs/1 and work_orders/1 states" do
    test "a state that is not one of the resource's is refused" do
      for filter <- [&Filters.runs/1, &Filters.work_orders/1] do
        assert {:error, changeset} = filter.(%{"state" => "started,bogus"})

        assert Errors.parameters(changeset).errors == [
                 %{
                   parameter: "state",
                   code: :not_allowed,
                   detail: "has an invalid entry"
                 }
               ]
      end
    end
  end

  describe "log_lines/1" do
    test "refuses a level that is not a log level" do
      assert {:error, changeset} = Filters.log_lines(%{"level" => "loud"})

      assert Errors.parameters(changeset).errors == [
               %{parameter: "level", code: :not_allowed, detail: "is invalid"}
             ]
    end
  end

  describe "work_orders/1" do
    test "refuses an id filter that isn't a UUID" do
      assert {:error, changeset} =
               Filters.work_orders(%{
                 "id" => "#{Ecto.UUID.generate()},nope",
                 "workflow_id" => "nope"
               })

      assert Enum.sort(Errors.parameters(changeset).errors) == [
               %{parameter: "id", code: :type, detail: "is invalid"},
               %{parameter: "workflow_id", code: :type, detail: "is invalid"}
             ]
    end
  end

  describe "collection_items/1" do
    test "counts an empty value as a value: an empty key stays, and an empty limit or cursor is refused" do
      Mox.stub(Lightning.MockConfig, :collections_default_stream_limit, fn ->
        25
      end)

      assert Filters.collection_items(%{"key" => ""}) ==
               {:ok, %{key: "", limit: 25}}

      for parameter <- ["limit", "cursor"] do
        assert {:error, changeset} =
                 Filters.collection_items(%{parameter => ""})

        assert Errors.parameters(changeset).errors == [
                 %{parameter: parameter, code: :type, detail: "is invalid"}
               ]
      end
    end
  end

  describe "page/1" do
    test "gives Repo.paginate/2 the page it would read from the request itself" do
      for params <- [
            %{"page" => "2", "page_size" => "50"},
            %{"page" => "5abc", "page_size" => "2.0"},
            %{"page" => "+3", "page_size" => " 4"},
            %{"page" => "0", "page_size" => "-1"},
            %{"page" => "", "page_size" => "abc"},
            %{"page" => ["2"], "page_size" => %{"a" => "2"}},
            %{"page" => "99999999999999999999", "page_size" => "1000"},
            %{"page" => 3, "page_size" => 0},
            %{"state" => "failed"}
          ] do
        assert scrivener(Filters.page(params)) == scrivener(params),
               inspect(params)
      end
    end

    test "answers the leading number, leaving out what it can't read" do
      assert Filters.page(%{"page" => "5abc", "page_size" => "2.0"}) ==
               [page: 5, page_size: 2]

      assert Filters.page(%{"page" => "abc", "page_size" => "0"}) == []
    end
  end

  defp scrivener(options) do
    config =
      Scrivener.Config.new(
        Lightning.Repo,
        Lightning.Repo.scrivener_defaults(),
        options
      )

    {config.page_number, config.page_size}
  end
end
