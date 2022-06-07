defmodule Lightning.InvocationTest do
  use Lightning.DataCase, async: true

  alias Lightning.Invocation
  alias Lightning.Repo
  import Lightning.InvocationFixtures
  import Lightning.ProjectsFixtures

  describe "invocation" do
    import Lightning.JobsFixtures
    alias Lightning.Invocation.{Run, Dataclip, Event}

    test "create/2 returns an Event with a run and a message" do
      job = job_fixture()

      assert {:ok,
              %{
                dataclip: %Dataclip{},
                event: %Event{},
                run: %Run{}
              }} =
               Invocation.create(
                 %{job_id: job.id, project_id: job.project_id, type: :webhook},
                 %{type: :http_request, body: %{"foo" => "bar"}}
               )
    end
  end

  describe "dataclips" do
    alias Lightning.Invocation.Dataclip

    @invalid_attrs %{body: nil, type: nil}

    test "list_dataclips/0 returns all dataclips" do
      dataclip = dataclip_fixture()
      assert Invocation.list_dataclips() == [dataclip]
    end

    test "list_dataclips/1 returns dataclips for project, desc by inserted_at" do
      project = project_fixture([])

      event = event_fixture(project_id: project.id)

      old_dataclip =
        dataclip_fixture(source_event_id: event.id)
        |> shift_inserted_at!(days: -2)

      new_dataclip =
        dataclip_fixture(source_event_id: event.id)
        |> shift_inserted_at!(days: -1)

      assert Invocation.list_dataclips(project)
             |> Enum.map(fn x -> x.id end) ==
               [event.dataclip_id, new_dataclip.id, old_dataclip.id]
    end

    test "get_dataclip!/1 returns the dataclip with given id" do
      dataclip = dataclip_fixture()
      assert Invocation.get_dataclip!(dataclip.id) == dataclip

      assert_raise Ecto.NoResultsError, fn ->
        Invocation.get_dataclip!(Ecto.UUID.generate())
      end
    end

    test "get_dataclip/1 returns the dataclip with given id" do
      event = event_fixture() |> Repo.preload(:dataclip)
      dataclip = event.dataclip
      assert Invocation.get_dataclip(dataclip.id) == dataclip
      assert Invocation.get_dataclip(Ecto.UUID.generate()) == nil

      run = run_fixture(event_id: event.id)

      assert Invocation.get_dataclip(run) == dataclip
    end

    test "create_dataclip/1 with valid data creates a dataclip" do
      valid_attrs = %{body: %{}, type: :http_request}

      assert {:ok, %Dataclip{} = dataclip} =
               Invocation.create_dataclip(valid_attrs)

      assert dataclip.body == %{}
      assert dataclip.type == :http_request
    end

    test "create_dataclip/1 with run_result type creates a dataclip" do
      run = run_fixture()
      attrs = %{body: %{}, type: :run_result, source_event_id: nil}

      # Commenting this out for now, in order to have truly versatile `cast_assoc`
      # we can't validate_required on `source_event_id`.
      # assert {:error, changeset} = Invocation.create_dataclip(attrs)
      # assert {:run_id, {"can't be blank", [validation: :required]}} in changeset.errors

      assert {:ok, %Dataclip{} = dataclip} =
               Invocation.create_dataclip(%{
                 attrs
                 | source_event_id: run.event_id
               })

      assert dataclip.body == %{}
      assert dataclip.type == :run_result

      assert dataclip.source_event_id == run.event_id
    end

    test "create_dataclip/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} =
               Invocation.create_dataclip(@invalid_attrs)
    end

    test "update_dataclip/2 with valid data updates the dataclip" do
      dataclip = dataclip_fixture()
      update_attrs = %{body: %{}, type: :global}

      assert {:ok, %Dataclip{} = dataclip} =
               Invocation.update_dataclip(dataclip, update_attrs)

      assert dataclip.body == %{}
      assert dataclip.type == :global
    end

    test "update_dataclip/2 with invalid data returns error changeset" do
      dataclip = dataclip_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Invocation.update_dataclip(dataclip, @invalid_attrs)

      assert dataclip == Invocation.get_dataclip!(dataclip.id)
    end

    test "delete_dataclip/1 sets the body to nil" do
      dataclip = dataclip_fixture()
      assert {:ok, %Dataclip{}} = Invocation.delete_dataclip(dataclip)

      assert %{body: nil} = Invocation.get_dataclip!(dataclip.id)
    end

    test "change_dataclip/1 returns a dataclip changeset" do
      dataclip = dataclip_fixture()
      assert %Ecto.Changeset{} = Invocation.change_dataclip(dataclip)
    end
  end

  describe "events" do
    alias Lightning.Invocation.Event
    import Lightning.JobsFixtures

    @invalid_attrs %{type: nil, dataclip: nil}

    test "create_event/1 with valid data creates an event" do
      dataclip = dataclip_fixture()
      job = job_fixture()

      valid_attrs = %{
        type: :webhook,
        project_id: job.project_id,
        dataclip_id: dataclip.id,
        job_id: job.id
      }

      assert {:ok, %Event{} = event} = Invocation.create_event(valid_attrs)
      event = Repo.preload(event, [:dataclip, :job])
      assert event.dataclip == dataclip
      assert event.job.id == job.id
      assert event.type == :webhook
    end

    test "create_event/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} =
               Invocation.create_event(@invalid_attrs)
    end
  end

  describe "runs" do
    alias Lightning.Invocation.Run

    import Lightning.InvocationFixtures

    @invalid_attrs %{event_id: nil}
    @valid_attrs %{
      exit_code: 42,
      finished_at: ~U[2022-02-02 11:49:00.000000Z],
      log: [],
      started_at: ~U[2022-02-02 11:49:00.000000Z]
    }

    test "list_runs/0 returns all runs" do
      run = run_fixture()
      assert Invocation.list_runs() == [run]
    end

    test "list_runs_for_project/2 returns runs ordered by inserted at desc" do
      project = project_fixture([])
      event = event_fixture(project_id: project.id)

      first_run = run_fixture(event_id: event.id) |> shift_inserted_at!(days: -1)
      second_run = run_fixture(event_id: event.id)

      assert Invocation.list_runs_for_project(project).entries == [
               second_run,
               first_run
             ]
    end

    test "get_run!/1 returns the run with given id" do
      run = run_fixture()
      assert Invocation.get_run!(run.id) == run
    end

    test "get_run!/1 returns the run for a given event" do
      event = event_fixture()
      run = run_fixture(event_id: event.id)
      assert Invocation.get_run!(event) == run
    end

    test "create_run/1 with valid data creates a run" do
      event = event_fixture()

      assert {:ok, %Run{} = run} =
               Invocation.create_run(
                 Map.merge(@valid_attrs, %{event_id: event.id})
               )

      assert run.exit_code == 42
      assert run.finished_at == ~U[2022-02-02 11:49:00.000000Z]
      assert run.log == []
      assert run.started_at == ~U[2022-02-02 11:49:00.000000Z]
    end

    test "create_run/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Invocation.create_run(@invalid_attrs)

      assert {:error, %Ecto.Changeset{errors: errors}} =
               Map.merge(@valid_attrs, %{event_id: Ecto.UUID.generate()})
               |> Invocation.create_run()

      assert event_id:
               {
                 "does not exist",
                 [constraint: :foreign, constraint_name: "runs_event_id_fkey"]
               } in errors
    end

    test "update_run/2 with valid data updates the run" do
      run = run_fixture()

      update_attrs = %{
        exit_code: 43,
        finished_at: ~U[2022-02-03 11:49:00.000000Z],
        log: [],
        started_at: ~U[2022-02-03 11:49:00.000000Z]
      }

      assert {:ok, %Run{} = run} = Invocation.update_run(run, update_attrs)
      assert run.exit_code == 43
      assert run.finished_at == ~U[2022-02-03 11:49:00.000000Z]
      assert run.log == []
      assert run.started_at == ~U[2022-02-03 11:49:00.000000Z]
    end

    test "update_run/2 with invalid data returns error changeset" do
      run = run_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Invocation.update_run(run, @invalid_attrs)

      assert run == Invocation.get_run!(run.id)
    end

    test "delete_run/1 deletes the run" do
      run = run_fixture()
      assert {:ok, %Run{}} = Invocation.delete_run(run)
      assert_raise Ecto.NoResultsError, fn -> Invocation.get_run!(run.id) end
    end

    test "change_run/1 returns a run changeset" do
      run = run_fixture()
      assert %Ecto.Changeset{} = Invocation.change_run(run)
    end
  end
end
