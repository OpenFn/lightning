defmodule Lightning.ExportWorkerTest do
  use Lightning.DataCase, async: true

  alias Lightning.WorkOrders.{ExportWorker, SearchParams}
  import Lightning.Factories

  setup do
    project = insert(:project)
    project_file = insert(:project_file, project: project)
    search_params = SearchParams.new(%{})

    %{jobs: [job], triggers: [trigger]} =
      workflow = insert(:simple_workflow, project: project)

    input_dataclip = insert(:dataclip, body: %{type: "input"}, project: project)

    output_dataclip =
      insert(:dataclip, body: %{type: "output"}, project: project)

    step_1 =
      insert(:step,
        input_dataclip: input_dataclip,
        output_dataclip: output_dataclip,
        job: job
      )

    step_2 =
      insert(:step,
        input_dataclip: input_dataclip,
        output_dataclip: output_dataclip,
        job: job
      )

    workorder =
      insert(:workorder,
        trigger: trigger,
        dataclip: input_dataclip,
        workflow: workflow,
        runs: [
          build(:run,
            starting_trigger: trigger,
            dataclip: input_dataclip,
            steps: [step_1, step_2],
            log_lines: [
              build(:log_line, step: step_1, message: "This is a log line"),
              build(:log_line, step: step_2, message: "This is another log line")
            ]
          ),
          build(:run,
            starting_trigger: trigger,
            dataclip: input_dataclip,
            steps: [step_1, step_2],
            log_lines: [
              build(:log_line, step: step_1, message: "Here is another log line"),
              build(:log_line, step: step_2, message: "Want more log lines ? :)")
            ]
          )
        ]
      )

    zip_file_path = "exports/#{project.id}/#{project_file.id}.zip"

    on_exit(fn ->
      if File.exists?(zip_file_path) do
        {_, 0} = System.cmd("rm", ["-r", Path.dirname(zip_file_path)])
      end
    end)

    {:ok,
     project: project,
     project_file: project_file,
     search_params: search_params,
     workorder: workorder |> Repo.preload(runs: [:run_steps]),
     dataclips: [input_dataclip, output_dataclip],
     zip_file_path: zip_file_path}
  end

  describe "perform/1" do
    test "exports all files into <project_file_id>.zip under the exports/<project.id> folder and updates zip file path of the project_file object",
         %{
           project: project,
           workorder: %{runs: [run_1, run_2]} = workorder,
           project_file: project_file,
           search_params: search_params,
           dataclips: [dataclip_1, dataclip_2],
           zip_file_path: zip_file_path
         } do
      refute project_file.path

      assert :ok ==
               ExportWorker.perform(%Oban.Job{
                 args: %{
                   "project_id" => project.id,
                   "project_file" => project_file.id,
                   "search_params" => to_oban_args(search_params)
                 }
               })

      project_file = Repo.reload(project_file)
      assert project_file.path == zip_file_path

      assert File.exists?(zip_file_path)

      {:ok, zip_handle} =
        :zip.zip_open(String.to_charlist(zip_file_path), [:memory])

      {:ok, file_list} = :zip.zip_list_dir(zip_handle)

      file_list =
        file_list
        |> Enum.reject(fn
          {:zip_comment, _} -> true
          _ -> false
        end)
        |> Enum.map(fn {_, file_name, _, _, _, _} ->
          to_string(file_name)
        end)

      expected_log_files = ["logs/#{run_1.id}.txt", "logs/#{run_2.id}.txt"]

      expected_dataclip_files = [
        "dataclips/#{dataclip_1.id}.json",
        "dataclips/#{dataclip_2.id}.json"
      ]

      expected_files = [
        "export.json" | expected_log_files ++ expected_dataclip_files
      ]

      assert MapSet.new(expected_files) == MapSet.new(file_list)

      actual_content = extract_and_read(zip_file_path, "export.json")

      actual_entities = Jason.decode!(actual_content)
      expected_entities = extract_entities(workorder)

      assert lists_equivalent?(
               expected_entities["runs"],
               actual_entities["runs"]
             )

      assert lists_equivalent?(
               expected_entities["steps"],
               actual_entities["steps"]
             )

      assert lists_equivalent?(
               expected_entities["run_steps"],
               actual_entities["run_steps"]
             )

      assert lists_equivalent?(
               expected_entities["work_orders"],
               actual_entities["work_orders"]
             )

      expected_dataclip_files = %{
        "dataclips/#{dataclip_1.id}.json" => %{
          "data" => %{"type" => "input"},
          "request" => nil
        },
        "dataclips/#{dataclip_2.id}.json" => %{
          "data" => %{"type" => "output"},
          "request" => nil
        }
      }

      for {file_path, expected_content} <- expected_dataclip_files do
        actual_content = extract_and_read(zip_file_path, file_path)
        assert Jason.decode!(actual_content) == expected_content
      end

      expected_log_files = %{
        "logs/#{run_1.id}.txt" => "This is a log line\nThis is another log line",
        "logs/#{run_2.id}.txt" =>
          "Here is another log line\nWant more log lines ? :)"
      }

      for {file_path, expected_content} <- expected_log_files do
        actual_content = extract_and_read(zip_file_path, file_path)
        assert actual_content == expected_content
      end

      :zip.zip_close(zip_handle)
    end

    test "marks project file as failed when export fails",
         %{
           project_file: project_file,
           search_params: search_params
         } do
      non_existent_project_id = Ecto.UUID.generate()

      assert {:error, :project_not_found} ==
               ExportWorker.perform(%Oban.Job{
                 args: %{
                   "project_id" => non_existent_project_id,
                   "project_file" => project_file.id,
                   "search_params" => to_oban_args(search_params)
                 }
               })

      project_file = Repo.reload(project_file)
      assert project_file.status == :failed
      assert is_nil(project_file.path)
    end

    test "marks project file as failed when the search params are invalid",
         %{project: project, project_file: project_file} do
      assert {:error, %Ecto.Changeset{}} =
               ExportWorker.perform(%Oban.Job{
                 args: %{
                   "project_id" => project.id,
                   "project_file" => project_file.id,
                   "search_params" => %{"status" => ["gone_status"]}
                 }
               })

      project_file = Repo.reload(project_file)
      assert project_file.status == :failed
      assert is_nil(project_file.path)
    end
  end

  describe "perform/1 dataclip scrubbing" do
    test "scrubs webhook auth secrets from exported http_request dataclips" do
      project = insert(:project)
      project_file = insert(:project_file, project: project)
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, workflow: workflow, type: :webhook)
      job = insert(:job, workflow: workflow)

      webhook_auth =
        insert(:webhook_auth_method,
          project: project,
          auth_type: :basic,
          username: "secretuser",
          password: "secretpass"
        )

      trigger
      |> Repo.preload(:webhook_auth_methods)
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:webhook_auth_methods, [webhook_auth])
      |> Repo.update!()

      http_dataclip =
        insert(:dataclip,
          project: project,
          type: :http_request,
          body: %{
            "data" => "keep-me",
            "authorization" => "Basic #{Base.encode64("secretuser:secretpass")}"
          }
        )

      step = insert(:step, job: job, input_dataclip: http_dataclip)

      insert(:run,
        work_order:
          build(:workorder,
            workflow: workflow,
            trigger: trigger,
            dataclip: http_dataclip,
            state: :success
          ),
        starting_trigger: trigger,
        dataclip: http_dataclip,
        state: :success,
        steps: [step]
      )

      zip_file_path = run_export!(project, project_file)

      content =
        extract_and_read(zip_file_path, "dataclips/#{http_dataclip.id}.json")

      refute content =~ "secretuser"
      refute content =~ "secretpass"
      refute content =~ Base.encode64("secretuser:secretpass")
      assert content =~ "***"
      assert content =~ "keep-me"
    end

    test "scrubs credential secrets from exported step_result dataclips" do
      project = insert(:project)
      project_file = insert(:project_file, project: project)
      workflow = insert(:workflow, project: project)
      trigger = insert(:trigger, workflow: workflow, type: :webhook)

      credential =
        insert(:credential, name: "Secret Cred", user: build(:user))
        |> with_body(%{body: %{"password" => "super-secret-value"}})

      project_credential =
        insert(:project_credential, credential: credential, project: project)

      job =
        insert(:job, workflow: workflow, project_credential: project_credential)

      input_dataclip = insert(:dataclip, project: project, body: %{})

      output_dataclip =
        insert(:dataclip,
          project: project,
          type: :step_result,
          body: %{"result" => "super-secret-value", "keep" => "visible"}
        )

      step =
        insert(:step,
          job: job,
          input_dataclip: input_dataclip,
          output_dataclip: output_dataclip,
          started_at: DateTime.utc_now()
        )

      insert(:run,
        work_order:
          build(:workorder,
            workflow: workflow,
            trigger: trigger,
            dataclip: input_dataclip,
            state: :success
          ),
        starting_trigger: trigger,
        dataclip: input_dataclip,
        state: :success,
        steps: [step]
      )

      zip_file_path = run_export!(project, project_file)

      content =
        extract_and_read(zip_file_path, "dataclips/#{output_dataclip.id}.json")

      refute content =~ "super-secret-value"
      assert content =~ "***"
      assert content =~ "visible"
    end
  end

  defp run_export!(project, project_file) do
    zip_file_path = "exports/#{project.id}/#{project_file.id}.zip"

    on_exit(fn ->
      if File.exists?(zip_file_path) do
        {_, 0} = System.cmd("rm", ["-r", Path.dirname(zip_file_path)])
      end
    end)

    assert :ok ==
             ExportWorker.perform(%Oban.Job{
               args: %{
                 "project_id" => project.id,
                 "project_file" => project_file.id,
                 "search_params" => to_oban_args(SearchParams.new(%{}))
               }
             })

    zip_file_path
  end

  def extract_and_read(zip_file_path, target_file_name) do
    {:ok, output_dir} = Briefly.create(directory: true)
    {_, 0} = System.cmd("unzip", [zip_file_path, "-d", output_dir])
    # For some reason, when Packmatic creates the zip file, there are
    # no permissions set on the files. 🤷
    {_, 0} = System.cmd("find", [output_dir | ~w"-type f -exec chmod 644 {} +"])
    {_, 0} = System.cmd("find", [output_dir | ~w"-type d -exec chmod 755 {} +"])
    file_path = Path.join([output_dir, target_file_name])
    File.read!(file_path)
  end

  # Oban stores job args as JSONB, so search params come back from the queue as
  # a string-keyed map with string values. Round-trip through JSON so perform/1
  # is handed exactly what it gets in production.
  defp to_oban_args(struct) do
    struct |> JSON.encode!() |> JSON.decode!()
  end

  defp lists_equivalent?(list1, list2) do
    list1 -- list2 == [] and list2 -- list1 == []
  end

  defp extract_entities(workorder) do
    runs = workorder.runs
    steps = Enum.flat_map(runs, & &1.steps)
    run_steps = Enum.flat_map(runs, & &1.run_steps)

    %{
      "runs" => Enum.map(runs, &format_run/1),
      "steps" => Enum.map(steps, &format_step/1),
      "run_steps" => Enum.map(run_steps, &format_run_step/1),
      "work_orders" => [format_work_order(workorder)]
    }
  end

  defp format_run(run) do
    %{
      "id" => run.id,
      "claimed_at" => run.claimed_at,
      "created_by_id" => run.created_by_id,
      "dataclip_id" => run.dataclip_id,
      "error_type" => run.error_type,
      "finished_at" => run.finished_at,
      "inserted_at" => DateTime.to_iso8601(run.inserted_at),
      "options" => %{
        "run_timeout_ms" => run.options.run_timeout_ms,
        "save_dataclips" => run.options.save_dataclips
      },
      "snapshot_id" => run.snapshot_id,
      "started_at" => run.started_at,
      "starting_job_id" => run.starting_job_id,
      "starting_trigger_id" => run.starting_trigger_id,
      "state" => Atom.to_string(run.state),
      "work_order_id" => run.work_order_id
    }
  end

  defp format_step(step) do
    %{
      "id" => step.id,
      "credential_id" => step.credential_id,
      "error_type" => step.error_type,
      "exit_reason" => step.exit_reason,
      "finished_at" => step.finished_at,
      "input_dataclip" => step.input_dataclip.id,
      "inserted_at" => DateTime.to_iso8601(step.inserted_at),
      "job_id" => step.job_id,
      "output_dataclip" => step.output_dataclip.id,
      "started_at" => step.started_at
    }
  end

  defp format_run_step(run_step) do
    %{
      "id" => run_step.id,
      "inserted_at" => DateTime.to_iso8601(run_step.inserted_at),
      "run_id" => run_step.run_id,
      "step_id" => run_step.step_id
    }
  end

  defp format_work_order(workorder) do
    %{
      "id" => workorder.id,
      "dataclip_id" => workorder.dataclip_id,
      "inserted_at" => DateTime.to_iso8601(workorder.inserted_at),
      "last_activity" => DateTime.to_iso8601(workorder.last_activity),
      "snapshot_id" => workorder.snapshot_id,
      "state" => Atom.to_string(workorder.state),
      "trigger_id" => workorder.trigger_id,
      "updated_at" => DateTime.to_iso8601(workorder.updated_at),
      "workflow_id" => workorder.workflow.id,
      "workflow_name" => workorder.workflow.name
    }
  end
end
