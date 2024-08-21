defmodule Lightning.ExportWorkerTest do
  use Lightning.DataCase, async: true

  alias Lightning.Storage.ProjectFileDefinition
  alias Lightning.WorkOrders.ExportWorker
  alias Lightning.WorkOrders.SearchParams

  import Lightning.Factories

  defp to_string_key_map(struct) do
    struct
    |> Map.from_struct()
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      Map.put(acc, Atom.to_string(key), value)
    end)
  end

  setup do
    project = insert(:project)
    project_file = insert(:project_file)
    search_params = SearchParams.new(%{})
    workflow = insert(:simple_workflow, project: project)

    workorder =
      insert(:workorder,
        workflow: workflow,
        trigger: build(:trigger),
        dataclip: build(:dataclip),
        last_activity: DateTime.utc_now()
      )

    run =
      insert(:run,
        work_order: workorder,
        starting_trigger: build(:trigger),
        dataclip: build(:dataclip),
        finished_at: build(:timestamp),
        state: :started
      )
      |> Repo.preload(:log_lines)

    {:ok,
     project: project,
     project_file: project_file,
     search_params: search_params,
     workorder: workorder,
     run: run}
  end

  describe "perform/1" do
    test "exporting with default search params would create a zip folder containing all the export files",
         %{
           project: project,
           project_file: project_file,
           search_params: search_params
         } do
      assert :ok ==
               ExportWorker.perform(%Oban.Job{
                 args: %{
                   "project_id" => project.id,
                   "project_file" => project_file.id,
                   "search_params" => to_string_key_map(search_params)
                 }
               })

      project_file = Repo.reload(project_file)

      storage_path =
        ProjectFileDefinition.storage_path_for_exports(project_file, ".zip")

      assert project_file.path == storage_path
    end
  end
end
