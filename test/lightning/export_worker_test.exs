defmodule Lightning.ExportWorkerTest do
  use Lightning.DataCase, async: true

  alias Lightning.WorkOrders.SearchParams

  import Lightning.Factories
  import Mox

  setup :verify_on_exit!

  defp to_string_key_map(struct) do
    struct
    |> Map.from_struct()
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      Map.put(acc, Atom.to_string(key), value)
    end)
  end

  describe "enqueue_export/2" do
    setup do
      project = insert(:project)
      project_file = insert(:project_file)
      search_params = SearchParams.new(%{})

      {:ok,
       project: project, project_file: project_file, search_params: search_params}
    end

    test "enqueue_export/3 enqueues an Oban job successfully", %{
      project: project,
      project_file: project_file,
      search_params: search_params
    } do
      assert :ok ==
               Lightning.WorkOrders.ExportWorker.enqueue_export(
                 project,
                 project_file,
                 search_params
               )

      job =
        Repo.one(
          from j in Oban.Job,
            where:
              j.queue == "history_exports" and
                j.args["project_id"] == ^project.id
        )

      assert job.args["project_id"] == project.id
      assert job.args["project_file"] == project_file.id
      assert job.args["search_params"] == to_string_key_map(search_params)
    end
  end
end
