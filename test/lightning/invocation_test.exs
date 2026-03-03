defmodule Lightning.InvocationTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.Runs
  alias Lightning.WorkOrders.SearchParams
  alias Lightning.Invocation
  alias Lightning.Repo
  alias Lightning.Workflows.Job

  require SearchParams

  defp build_workflow(opts) do
    job = build(:job)
    trigger = build(:trigger)

    workflow =
      build(:workflow, opts)
      |> with_job(job)
      |> with_trigger(trigger)
      |> with_edge({trigger, job})
      |> insert()

    {:ok, snapshot} =
      Lightning.Workflows.Snapshot.create(workflow)

    %{
      workflow: workflow,
      snapshot: snapshot,
      trigger: trigger |> Repo.reload!(),
      job: job |> Repo.reload!()
    }
  end

  describe "dataclips" do
    alias Lightning.Invocation.Dataclip

    @invalid_attrs %{body: nil, type: nil}

    test "list_dataclips/0 returns all dataclips" do
      dataclip = insert(:dataclip)

      assert Invocation.list_dataclips()
             |> Enum.map(fn dataclip -> dataclip.id end) == [dataclip.id]
    end

    test "list_dataclips/1 returns dataclips for project, desc by inserted_at" do
      project = insert(:project)

      old_dataclip =
        insert(:dataclip, project: project)
        |> shift_inserted_at!(days: -2)

      new_dataclip =
        insert(:dataclip, project: project)
        |> shift_inserted_at!(days: -1)

      assert Invocation.list_dataclips(project)
             |> Enum.map(fn x -> x.id end) ==
               [new_dataclip.id, old_dataclip.id]
    end

    test "get_dataclip!/1 returns the dataclip with given id" do
      dataclip = insert(:dataclip, body: nil)

      assert Invocation.get_dataclip!(dataclip.id) |> Repo.preload(:project) ==
               dataclip

      assert_raise Ecto.NoResultsError, fn ->
        Invocation.get_dataclip!(Ecto.UUID.generate())
      end
    end

    test "get_dataclip/1 returns the dataclip with given id" do
      dataclip = insert(:dataclip, body: nil)

      assert Invocation.get_dataclip(dataclip.id) |> Repo.preload(:project) ==
               dataclip

      assert Invocation.get_dataclip(Ecto.UUID.generate()) == nil

      step = insert(:step, input_dataclip: dataclip)

      assert Invocation.get_dataclip(step) |> Repo.preload(:project) ==
               dataclip
    end

    test "create_dataclip/1 with valid data creates a dataclip" do
      project = insert(:project)
      valid_attrs = %{body: %{}, project_id: project.id, type: :http_request}

      assert {:ok, %Dataclip{} = dataclip} =
               Invocation.create_dataclip(valid_attrs)

      assert dataclip.body == %{}
      assert dataclip.type == :http_request
    end

    test "create_dataclip/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} =
               Invocation.create_dataclip(@invalid_attrs)
    end

    test "huge dataclips can get saved" do
      project = insert(:project)

      body =
        Map.new(1..20_000, fn _n ->
          {Ecto.UUID.generate(), Ecto.UUID.generate()}
        end)

      assert {:ok, _dataclip} =
               Dataclip.new(%{
                 id: Ecto.UUID.generate(),
                 project_id: project.id,
                 body: body,
                 type: :step_result
               })
               |> Repo.insert()
    end

    test "update_dataclip/2 with valid data updates the dataclip" do
      dataclip = insert(:dataclip)
      update_attrs = %{body: %{}, type: :global}

      assert {:ok, %Dataclip{} = dataclip} =
               Invocation.update_dataclip(dataclip, update_attrs)

      assert dataclip.body == %{}
      assert dataclip.type == :global
    end

    test "update_dataclip/2 with invalid data returns error changeset" do
      dataclip = insert(:dataclip, body: nil)

      assert {:error, %Ecto.Changeset{}} =
               Invocation.update_dataclip(dataclip, @invalid_attrs)

      assert dataclip ==
               Invocation.get_dataclip!(dataclip.id)
               |> Repo.preload(:project)
    end

    test "delete_dataclip/1 sets the body to nil" do
      dataclip = insert(:dataclip)
      assert {:ok, %Dataclip{}} = Invocation.delete_dataclip(dataclip)

      assert %{body: nil} = Invocation.get_dataclip!(dataclip.id)
    end

    test "change_dataclip/1 returns a dataclip changeset" do
      dataclip = insert(:dataclip)
      assert %Ecto.Changeset{} = Invocation.change_dataclip(dataclip)
    end

    test "get_dataclip_with_body!/1 returns dataclip with body as JSON text" do
      project = insert(:project)

      # Test with http_request type - should wrap body in {"data": ..., "request": ...}
      http_dataclip =
        insert(:dataclip,
          body: %{"foo" => "bar"},
          request: %{"headers" => "list"},
          type: :http_request,
          project: project
        )

      result = Invocation.get_dataclip_with_body!(http_dataclip.id)

      assert result.id == http_dataclip.id
      assert result.type == :http_request
      assert result.updated_at == http_dataclip.updated_at
      # Body should be JSON text string, not Elixir map
      assert is_binary(result.body_json)
      # Should be wrapped structure for http_request
      parsed = Jason.decode!(result.body_json)
      assert parsed["data"] == %{"foo" => "bar"}
      assert parsed["request"] == %{"headers" => "list"}

      # Test with step_result type - should NOT wrap body
      step_dataclip =
        insert(:dataclip,
          body: %{"baz" => "qux"},
          type: :step_result,
          project: project
        )

      result = Invocation.get_dataclip_with_body!(step_dataclip.id)

      assert result.id == step_dataclip.id
      assert result.type == :step_result
      assert is_binary(result.body_json)
      parsed = Jason.decode!(result.body_json)
      assert parsed == %{"baz" => "qux"}

      # Test with kafka type - should wrap body in {"data": ..., "request": ...}
      kafka_dataclip =
        insert(:dataclip,
          body: %{"kafka" => "data"},
          request: %{"topic" => "test"},
          type: :kafka,
          project: project
        )

      result = Invocation.get_dataclip_with_body!(kafka_dataclip.id)

      assert result.type == :kafka
      assert is_binary(result.body_json)
      parsed = Jason.decode!(result.body_json)
      assert parsed["data"] == %{"kafka" => "data"}
      assert parsed["request"] == %{"topic" => "test"}

      # Test that it raises when dataclip doesn't exist
      assert_raise Ecto.NoResultsError, fn ->
        Invocation.get_dataclip_with_body!(Ecto.UUID.generate())
      end
    end
  end

  describe "list_dataclips_for_job/2" do
    test "returns empty list if there are no input dataclips" do
      assert [] =
               Invocation.list_dataclips_for_job(
                 %Job{id: Ecto.UUID.generate()},
                 5
               )
    end

    test "returns a list up to a limit of dataclips" do
      %{jobs: [job | _rest]} = insert(:simple_workflow)

      [_dataclip1, dataclip2, dataclip3] =
        Enum.map(1..3, fn i ->
          insert(:dataclip,
            body: %{"field" => "value"},
            request: %{"headers" => "list"},
            type: :http_request,
            inserted_at: DateTime.add(DateTime.utc_now(), i, :millisecond)
          )
          |> tap(&insert(:step, input_dataclip: &1, job: job))
        end)

      # string limit works too
      assert_dataclips_list(
        [dataclip3, dataclip2],
        Invocation.list_dataclips_for_job(%Job{id: job.id}, "2")
      )
    end

    test "returns latest dataclips for a job selecting the body as input" do
      %{jobs: [job1, job2 | _rest]} = insert(:complex_workflow)

      insert(:step,
        input_dataclip:
          build(:dataclip,
            body: %{"field" => "value"},
            request: %{"headers" => "list"},
            type: :http_request
          ),
        job: job2
      )

      inserted_at = DateTime.utc_now()

      dataclips =
        Enum.map(1..6, fn i ->
          insert(:dataclip,
            body: %{"foo#{i}" => "bar#{i}"},
            request: %{"headers" => "list#{i}"},
            inserted_at: DateTime.add(inserted_at, i, :millisecond)
          )
          |> tap(fn dataclip ->
            insert(:step, input_dataclip: dataclip, job: job1)

            assert dataclip.body == %{"foo#{i}" => "bar#{i}"}
          end)
        end)
        |> Enum.drop(1)
        |> Enum.sort_by(& &1.inserted_at, :desc)

      assert_dataclips_list(
        dataclips,
        Invocation.list_dataclips_for_job(job1, 5)
      )
    end

    test "filters out wiped dataclips" do
      %{jobs: [job1 | _rest]} = insert(:simple_workflow)

      insert(:step,
        input_dataclip:
          build(:dataclip, body: nil, wiped_at: DateTime.utc_now()),
        job: job1
      )

      dataclip =
        insert(:dataclip,
          body: %{"foo" => "bar"},
          request: %{"headers" => "list"}
        )

      insert(:step, input_dataclip: dataclip, job: job1)

      assert_dataclips_list(
        [dataclip],
        Invocation.list_dataclips_for_job(job1, 5)
      )
    end
  end

  describe "list_dataclips_for_job/3" do
    test "returns empty list if there are no input dataclips" do
      assert [] =
               Invocation.list_dataclips_for_job(
                 %Job{id: Ecto.UUID.generate()},
                 %{},
                 limit: 5
               )
    end

    test "returns dataclips without the body" do
      %{jobs: [job1, job2 | _rest]} = insert(:complex_workflow)

      insert(:step,
        input_dataclip:
          build(:dataclip,
            body: %{"field" => "value"},
            request: %{"headers" => "list"},
            type: :http_request
          ),
        job: job2
      )

      insert(:step,
        input_dataclip:
          build(:dataclip,
            body: %{"field" => "value"},
            request: %{"headers" => "list"},
            type: :saved_input
          ),
        job: job1
      )

      inserted_at = DateTime.utc_now()

      dataclips =
        Enum.map(1..6, fn i ->
          dataclip =
            insert(:dataclip,
              body: %{"foo#{i}" => "bar#{i}"},
              request: %{"headers" => "list#{i}"},
              type: :http_request,
              inserted_at: DateTime.add(inserted_at, i, :millisecond)
            )
            |> Map.delete(:project)

          insert(:step, input_dataclip: dataclip, job: job1)

          assert dataclip.body == %{"foo#{i}" => "bar#{i}"}

          dataclip
          |> Map.put(:request, nil)
        end)
        |> Enum.drop(1)
        |> Enum.sort_by(& &1.inserted_at, :desc)

      assert Enum.map(dataclips, &Map.merge(&1, %{body: nil, project: nil})) ==
               Invocation.list_dataclips_for_job(
                 job1,
                 %{type: "http_request"},
                 limit: 5
               )
               |> Enum.map(&Map.merge(&1, %{project: nil}))
    end

    test "returns latest dataclips for a job filtering by type" do
      %{jobs: [job1, job2 | _rest]} = insert(:complex_workflow)

      insert(:step,
        input_dataclip:
          build(:dataclip,
            body: %{"field" => "value"},
            request: %{"headers" => "list"},
            type: :http_request
          ),
        job: job2
      )

      insert(:step,
        input_dataclip:
          build(:dataclip,
            body: %{"field" => "value"},
            request: %{"headers" => "list"},
            type: :saved_input
          ),
        job: job1
      )

      inserted_at = DateTime.utc_now()

      dataclips =
        Enum.map(1..6, fn i ->
          dataclip =
            insert(:dataclip,
              body: %{"foo#{i}" => "bar#{i}"},
              request: %{"headers" => "list#{i}"},
              type: :http_request,
              inserted_at: DateTime.add(inserted_at, i, :millisecond)
            )
            |> Map.delete(:project)

          insert(:step, input_dataclip: dataclip, job: job1)

          assert dataclip.body == %{"foo#{i}" => "bar#{i}"}

          dataclip
          |> Map.update(:body, nil, fn body ->
            %{"data" => body, "request" => dataclip.request}
          end)
          |> Map.put(:request, nil)
        end)
        |> Enum.drop(1)
        |> Enum.sort_by(& &1.inserted_at, :desc)

      assert_dataclips_list(
        dataclips,
        Invocation.list_dataclips_for_job(job1, %{type: "http_request"},
          limit: 5
        )
      )
    end

    test "returns latest dataclips for a job filtering by id" do
      %{jobs: [job1 | _rest]} = insert(:complex_workflow)

      [%{id: dataclip_id} | _ignored] =
        Enum.map(1..10, fn _i ->
          insert(:dataclip) |> tap(&insert(:step, input_dataclip: &1, job: job1))
        end)

      Enum.each(1..8, fn i ->
        prefix = String.slice(dataclip_id, 0, i)

        dataclips =
          Invocation.list_dataclips_for_job(
            job1,
            %{id_prefix: prefix},
            limit: 10
          )

        assert Enum.any?(dataclips, &(&1.id == dataclip_id))
      end)
    end

    test "doesn't return a dataclip if the wrong text is entered" do
      %{jobs: [job1 | _rest]} = insert(:complex_workflow)

      [%{id: dataclip_id} | _ignored] =
        Enum.map(1..10, fn _i ->
          insert(:dataclip) |> tap(&insert(:step, input_dataclip: &1, job: job1))
        end)

      # replace the actual 3rd character with some random number
      prefix = String.slice(dataclip_id, 0, 2) <> "4"

      dataclips =
        Invocation.list_dataclips_for_job(
          job1,
          %{id_prefix: prefix},
          limit: 10
        )

      # ensure that the dataclip isn't found:
      # i.e., refute that writing "ab4" matches a dataclip with UUID prefix "ab7"
      refute Enum.any?(dataclips, &(&1.id == dataclip_id))
    end

    test "filters out wiped dataclips" do
      %{jobs: [job1 | _rest]} = insert(:simple_workflow)

      insert(:step,
        input_dataclip:
          build(:dataclip, body: nil, wiped_at: DateTime.utc_now()),
        job: job1
      )

      dataclip =
        insert(:dataclip,
          body: %{"foo" => "bar"},
          request: %{"headers" => "list"},
          type: :http_request
        )
        |> then(
          &Map.update(&1, :body, nil, fn body ->
            %{"data" => body, "request" => &1.request}
          end)
        )
        |> Map.drop([:project, :request])

      insert(:step, input_dataclip: dataclip, job: job1)

      assert_dataclips_list(
        [dataclip],
        Invocation.list_dataclips_for_job(
          job1,
          %{type: "http_request"},
          limit: 5
        )
      )
    end

    test "filters dataclips by name prefix case-insensitively" do
      project = insert(:project)
      %{jobs: [job1 | _rest]} = insert(:complex_workflow, project: project)

      # Create dataclips with different names
      named_dataclip =
        insert(:dataclip,
          name: "My Test Dataclip",
          body: %{"foo" => "bar"},
          type: :http_request,
          project: project
        )

      other_named_dataclip =
        insert(:dataclip,
          name: "Another Dataclip",
          body: %{"baz" => "qux"},
          type: :http_request,
          project: project
        )

      # Create dataclip without name
      insert(:dataclip,
        name: nil,
        body: %{"without" => "name"},
        type: :http_request
      )
      |> tap(&insert(:step, input_dataclip: &1, job: job1))

      # Associate named dataclips with job
      insert(:step, input_dataclip: named_dataclip, job: job1)
      insert(:step, input_dataclip: other_named_dataclip, job: job1)

      # Test case-insensitive search for "my"
      assert_dataclips_list(
        [named_dataclip],
        Invocation.list_dataclips_for_job(
          job1,
          %{name_part: "my"},
          limit: 10
        )
      )

      # Test case-insensitive search for "MY"
      assert_dataclips_list(
        [named_dataclip],
        Invocation.list_dataclips_for_job(
          job1,
          %{name_part: "MY"},
          limit: 10
        )
      )

      # Test partial match "anoth"
      assert_dataclips_list(
        [other_named_dataclip],
        Invocation.list_dataclips_for_job(
          job1,
          %{name_part: "anoth"},
          limit: 10
        )
      )

      # Test no matches
      assert [] =
               Invocation.list_dataclips_for_job(
                 job1,
                 %{name_part: "nonexistent"},
                 limit: 10
               )
    end

    test "filters dataclips to only named ones" do
      project = insert(:project)
      %{jobs: [job1 | _rest]} = insert(:complex_workflow, project: project)

      # Create named dataclips
      named_dataclip1 =
        insert(:dataclip,
          name: "First Named",
          body: %{"foo" => "bar"},
          type: :http_request,
          project: project
        )

      named_dataclip2 =
        insert(:dataclip,
          name: "Second Named",
          body: %{"baz" => "qux"},
          type: :http_request,
          project: project
        )

      # Create dataclips without names
      insert(:dataclip,
        name: nil,
        body: %{"without" => "name1"},
        type: :http_request
      )
      |> tap(&insert(:step, input_dataclip: &1, job: job1))

      insert(:dataclip,
        name: nil,
        body: %{"without" => "name2"},
        type: :http_request
      )
      |> tap(&insert(:step, input_dataclip: &1, job: job1))

      # Associate named dataclips with job
      insert(:step, input_dataclip: named_dataclip1, job: job1)
      insert(:step, input_dataclip: named_dataclip2, job: job1)

      # Test named_only filter
      results =
        Invocation.list_dataclips_for_job(
          job1,
          %{named_only: true},
          limit: 10
        )

      assert length(results) == 2
      assert_dataclips_list([named_dataclip2, named_dataclip1], results)

      # Test without named_only filter - should return all dataclips
      all_results =
        Invocation.list_dataclips_for_job(
          job1,
          %{},
          limit: 10
        )

      assert length(all_results) == 4
    end
  end

  describe "steps" do
    test "list_steps/0 returns all steps" do
      step = insert(:step)
      assert Invocation.list_steps() |> Enum.map(fn s -> s.id end) == [step.id]
    end

    test "get_step!/1 returns the step with given id" do
      step = insert(:step)

      actual_step = Invocation.get_step!(step.id)

      assert actual_step.id == step.id
      assert actual_step.input_dataclip_id == step.input_dataclip_id
      assert actual_step.job_id == step.job_id
    end

    test "change_step/1 returns a step changeset" do
      step = insert(:step)
      assert %Ecto.Changeset{} = Invocation.change_step(step)
    end
  end

  defp actual_filter_by_status(project, status) do
    Invocation.search_workorders(
      %Lightning.Projects.Project{
        id: project.id
      },
      SearchParams.new(status),
      %{"page" => 1, "page_size" => 10}
    ).entries
  end

  defp create_work_order(project, snapshot, workflow, job, trigger, now, seconds) do
    dataclip = insert(:dataclip, project: project)

    wo =
      insert(
        :workorder,
        workflow: workflow,
        trigger: trigger,
        dataclip: dataclip,
        snapshot: snapshot
      )

    run =
      insert(:run,
        work_order: wo,
        dataclip: dataclip,
        starting_trigger: trigger,
        snapshot: snapshot
      )

    {:ok, step} =
      Runs.start_step(run, %{
        "job_id" => job.id,
        "input_dataclip_id" => dataclip.id,
        "started_at" => now |> Timex.shift(seconds: seconds),
        "finished_at" =>
          now
          |> Timex.shift(seconds: seconds + 10),
        "step_id" => Ecto.UUID.generate()
      })

    %{work_order: wo, step: step}
  end

  defp get_simplified_page(project, page, filter) do
    Invocation.search_workorders(
      %Lightning.Projects.Project{
        id: project.id
      },
      filter,
      page
    ).entries
  end

  describe "search_workorders_for_retry/2" do
    test "returns workorders without preloading and without wiped dataclips" do
      project = insert(:project)
      dataclip = insert(:dataclip)
      wiped_dataclip = insert(:dataclip, wiped_at: Timex.now())

      %{workflow: workflow, trigger: trigger} =
        build_workflow(project: project)

      workorders =
        insert_list(2, :workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip
        )

      insert_list(2, :workorder,
        workflow: workflow,
        trigger: trigger,
        dataclip: wiped_dataclip
      )

      assert found_workorders =
               Invocation.search_workorders_for_retry(
                 project,
                 SearchParams.new(%{"status" => SearchParams.status_list()})
               )

      assert MapSet.new(workorders, & &1.id) ==
               MapSet.new(found_workorders, & &1.id)

      refute Enum.any?(found_workorders, &Ecto.assoc_loaded?(&1.dataclip))
      refute Enum.any?(found_workorders, &Ecto.assoc_loaded?(&1.snapshot))
      refute Enum.any?(found_workorders, &Ecto.assoc_loaded?(&1.workflow))
      refute Enum.any?(found_workorders, &Ecto.assoc_loaded?(&1.runs))
    end
  end

  describe "search_workorders/1" do
    test "returns workorders ordered inserted at desc, with nulls first" do
      project = insert(:project)
      dataclip = insert(:dataclip)

      %{workflow: workflow, trigger: trigger, job: job} =
        build_workflow(project: project, name: "chw-help")

      workorders =
        insert_list(4, :workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip
        )

      now = Timex.now()

      runs =
        Enum.map(workorders, fn workorder ->
          insert(:run,
            work_order: workorder,
            dataclip: dataclip,
            starting_trigger: trigger
          )
        end)

      runs
      |> Enum.with_index()
      |> Enum.each(fn {run, index} ->
        started_shift = -50 - index * 10
        finished_shift = -40 - index * 10

        Runs.start_step(run, %{
          "job_id" => job.id,
          "input_dataclip_id" => dataclip.id,
          "started_at" => now |> Timex.shift(seconds: started_shift),
          "finished_at" => now |> Timex.shift(seconds: finished_shift),
          "step_id" => Ecto.UUID.generate()
        })
      end)

      found_workorders =
        Invocation.search_workorders(%Lightning.Projects.Project{
          id: workflow.project_id
        })

      assert found_workorders.page_number == 1
      assert found_workorders.total_pages == 1

      assert workorders
             |> Enum.reverse()
             |> Enum.map(fn workorder -> workorder.id end) ==
               found_workorders.entries
               |> Enum.map(fn workorder -> workorder.id end)
    end
  end

  describe "search_workorders/3" do
    test "filters workorders by two statuses" do
      project = insert(:project)
      workflow = insert(:workflow, project: project)

      insert_list(3, :workorder, workflow: workflow, state: :pending)
      insert_list(2, :workorder, workflow: workflow, state: :crashed)
      insert_list(2, :workorder, workflow: workflow, state: :failed)
      insert_list(1, :workorder, workflow: workflow, state: :pending)
      insert_list(1, :workorder, workflow: workflow, state: :crashed)

      assert %{
               page_number: 1,
               page_size: 10,
               total_entries: 7,
               total_pages: 1,
               entries: entries
             } =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{"status" => ["pending", "crashed"]}),
                 %{
                   page: 1,
                   page_size: 10
                 }
               )

      assert %{
               :pending => 4,
               :crashed => 3
             } = Enum.map(entries, & &1.state) |> Enum.frequencies()
    end

    test "filters workorders by all statuses" do
      project = insert(:project)
      workflow = insert(:workflow, project: project)

      count =
        SearchParams.status_list()
        |> Enum.map(fn status ->
          insert(:workorder, workflow: workflow, state: status)
        end)
        |> Enum.count()

      assert %{
               page_number: 1,
               page_size: 10,
               total_entries: ^count,
               total_pages: 1,
               entries: entries
             } =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{"status" => SearchParams.status_list()}),
                 %{
                   page: 1,
                   page_size: 10
                 }
               )

      assert SearchParams.status_list() |> Enum.frequencies() ==
               Enum.map(entries, & &1.state)
               |> Enum.frequencies()
               |> Map.new(fn {status, count} ->
                 {Atom.to_string(status), count}
               end)
    end

    test "returns a sequence of workorders pages" do
      project = insert(:project)
      workflow = insert(:workflow, project: project)

      insert_list(10, :workorder, workflow: workflow, state: :crashed)

      %{
        page_number: page_number,
        page_size: page_size,
        total_entries: total_entries,
        total_pages: total_pages,
        entries: entries
      } =
        Invocation.search_workorders(
          project,
          SearchParams.new(%{"status" => ["crashed"]}),
          %{
            page: 1,
            page_size: 4
          }
        )

      assert {page_number, page_size, total_entries, total_pages,
              length(entries)} == {1, 4, 10, 3, 4}

      %{
        page_number: page_number,
        page_size: page_size,
        total_entries: total_entries,
        total_pages: total_pages,
        entries: entries
      } =
        Invocation.search_workorders(
          project,
          SearchParams.new(%{"status" => ["crashed"]}),
          %{
            page: 2,
            page_size: 4
          }
        )

      assert {page_number, page_size, total_entries, total_pages,
              length(entries)} == {2, 4, 10, 3, 4}

      %{
        page_number: page_number,
        page_size: page_size,
        total_entries: total_entries,
        total_pages: total_pages,
        entries: entries
      } =
        Invocation.search_workorders(
          project,
          SearchParams.new(%{"status" => ["crashed"]}),
          %{
            page: 3,
            page_size: 4
          }
        )

      assert {page_number, page_size, total_entries, total_pages,
              length(entries)} == {3, 4, 10, 3, 2}
    end

    test "returns paginated workorders with ordering" do
      project = insert(:project)

      %{workflow: workflow1, trigger: trigger1, job: job1, snapshot: snapshot} =
        build_workflow(project: project, name: "workflow-1")

      now = Timex.now()

      %{work_order: wf1_wo1, step: _wf1_step1} =
        create_work_order(project, snapshot, workflow1, job1, trigger1, now, 10)

      %{work_order: wf1_wo2, step: _wf1_step2} =
        create_work_order(project, snapshot, workflow1, job1, trigger1, now, 20)

      %{work_order: wf1_wo3, step: _wf1_step3} =
        create_work_order(project, snapshot, workflow1, job1, trigger1, now, 30)

      %{workflow: workflow2, trigger: trigger2, job: job2, snapshot: snapshot} =
        build_workflow(project: project, name: "workflow-2")

      %{work_order: wf2_wo1, step: _wf2_step1} =
        create_work_order(project, snapshot, workflow2, job2, trigger2, now, 40)

      %{work_order: wf2_wo2, step: _wf2_step2} =
        create_work_order(project, snapshot, workflow2, job2, trigger2, now, 50)

      %{work_order: wf2_wo3, step: _wf2_step3} =
        create_work_order(project, snapshot, workflow2, job2, trigger2, now, 60)

      %{workflow: workflow3, trigger: trigger3, job: job3, snapshot: snapshot} =
        build_workflow(project: project, name: "workflow-3")

      %{work_order: wf3_wo1, step: _wf3_step1} =
        create_work_order(project, snapshot, workflow3, job3, trigger3, now, 70)

      %{work_order: wf3_wo2, step: _wf3_step2} =
        create_work_order(project, snapshot, workflow3, job3, trigger3, now, 80)

      %{work_order: wf3_wo3, step: _wf3_step3} =
        create_work_order(project, snapshot, workflow3, job3, trigger3, now, 90)

      ### PAGE 1 -----------------------------------------------------------------------

      page_one_result =
        get_simplified_page(
          project,
          %{"page" => 1, "page_size" => 3},
          SearchParams.new(%{
            "crash" => "true",
            "failure" => "true",
            "pending" => "true",
            "timeout" => "true",
            "success" => "true"
          })
        )

      # all work_orders in page_one are ordered by finished_at

      expected_order = [wf3_wo3.id, wf3_wo2.id, wf3_wo1.id]

      assert expected_order ==
               page_one_result |> Enum.map(fn workorder -> workorder.id end)

      ### PAGE 2 -----------------------------------------------------------------------

      page_two_result =
        get_simplified_page(
          project,
          %{"page" => 2, "page_size" => 3},
          SearchParams.new(%{
            "crash" => "true",
            "failure" => "true",
            "pending" => "true",
            "timeout" => "true",
            "success" => "true"
          })
        )

      # all work_orders in page_two are ordered by finished_at
      expected_order = [wf2_wo3.id, wf2_wo2.id, wf2_wo1.id]

      assert expected_order ==
               page_two_result |> Enum.map(fn workorder -> workorder.id end)

      ### PAGE 3 -----------------------------------------------------------------------

      page_three_result =
        get_simplified_page(
          project,
          %{"page" => 3, "page_size" => 3},
          SearchParams.new(%{
            "crash" => "true",
            "failure" => "true",
            "pending" => "true",
            "timeout" => "true",
            "success" => "true"
          })
        )

      # all work_orders in page_three are ordered by finished_at
      expected_order = [wf1_wo3.id, wf1_wo2.id, wf1_wo1.id]

      assert expected_order ==
               page_three_result |> Enum.map(fn workorder -> workorder.id end)
    end

    test "filters workorders by state" do
      project = insert(:project)
      workflow = insert(:workflow, project: project)

      pending_workorder = insert(:workorder, workflow: workflow, state: :pending)
      running_workorder = insert(:workorder, workflow: workflow, state: :running)
      success_workorder = insert(:workorder, workflow: workflow, state: :success)
      crashed_workorder = insert(:workorder, workflow: workflow, state: :crashed)
      failed_workorder = insert(:workorder, workflow: workflow, state: :failed)
      killed_workorder = insert(:workorder, workflow: workflow, state: :killed)

      [found_pending_workorder] =
        actual_filter_by_status(project, %{"status" => ["pending"]})

      [found_running_workorder] =
        actual_filter_by_status(project, %{"status" => ["running"]})

      [found_success_workorder] =
        actual_filter_by_status(project, %{"status" => ["success"]})

      [found_crashed_workorder] =
        actual_filter_by_status(project, %{"status" => ["crashed"]})

      [found_failed_workorder] =
        actual_filter_by_status(project, %{"status" => ["failed"]})

      [found_killed_workorder] =
        actual_filter_by_status(project, %{"status" => ["killed"]})

      assert found_pending_workorder.id == pending_workorder.id
      assert found_running_workorder.id == running_workorder.id
      assert found_success_workorder.id == success_workorder.id
      assert found_crashed_workorder.id == crashed_workorder.id
      assert found_failed_workorder.id == failed_workorder.id
      assert found_killed_workorder.id == killed_workorder.id
    end

    test "filters workorders by workflow id" do
      project = insert(:project)

      workflow1 = insert(:workflow, project: project, name: "workflow-1")
      workflow2 = insert(:workflow, project: project, name: "workflow-2")

      insert_list(5, :workorder, workflow: workflow1, state: :success)
      insert_list(3, :workorder, workflow: workflow2, state: :crashed)

      workflow1_results =
        Invocation.search_workorders(
          project,
          SearchParams.new(%{"workflow_id" => workflow1.id})
        ).entries

      assert length(workflow1_results) == 5

      assert Enum.all?(workflow1_results, fn wo ->
               wo.workflow_id == workflow1.id
             end)

      workflow2_results =
        Invocation.search_workorders(
          project,
          SearchParams.new(%{"workflow_id" => workflow2.id})
        ).entries

      assert length(workflow2_results) == 3

      assert Enum.all?(workflow2_results, fn wo ->
               wo.workflow_id == workflow2.id
             end)
    end

    test "filters workorders by workorder id" do
      project = insert(:project)

      workflow = insert(:workflow, project: project, name: "workflow-1")

      workorder_1 = insert(:workorder, workflow: workflow, state: :success)

      workorder_2 = insert(:workorder, workflow: workflow, state: :success)

      page_result =
        Invocation.search_workorders(
          project,
          SearchParams.new(%{"workorder_id" => workorder_1.id})
        )

      assert [entry] = page_result.entries
      assert entry.id == workorder_1.id

      page_result =
        Invocation.search_workorders(
          project,
          SearchParams.new(%{"workorder_id" => workorder_2.id})
        )

      assert [entry] = page_result.entries
      assert entry.id == workorder_2.id
    end

    test "filters workorders by last_activity" do
      project = insert(:project)
      _dataclip = insert(:dataclip)

      %{workflow: workflow} =
        build_workflow(project: project, name: "chw-help")

      now = Timex.now()
      past_time = Timex.shift(now, days: -1)
      future_time = Timex.shift(now, days: 1)

      _wo_past =
        insert(:workorder,
          workflow: workflow,
          inserted_at: past_time,
          last_activity: past_time
        )

      wo_now =
        insert(:workorder,
          workflow: workflow,
          inserted_at: past_time,
          last_activity: now
        )

      _wo_future =
        insert(:workorder,
          workflow: workflow,
          inserted_at: past_time,
          last_activity: future_time
        )

      [found_workorder] =
        Invocation.search_workorders(
          project,
          SearchParams.new(%{
            "date_after" => Timex.shift(now, minutes: -1),
            "date_before" => Timex.shift(now, minutes: 1)
          })
        ).entries

      assert found_workorder.id == wo_now.id
    end

    test "filters workorders by workorder inserted_at" do
      project = insert(:project)
      workflow = insert(:workflow, project: project)

      now = Timex.now()
      past_time = Timex.shift(now, days: -1)
      future_time = Timex.shift(now, days: 1)

      insert(:workorder, workflow: workflow, inserted_at: past_time)
      wo_now = insert(:workorder, workflow: workflow, inserted_at: now)
      insert(:workorder, workflow: workflow, inserted_at: future_time)

      [found_workorder] =
        Invocation.search_workorders(
          project,
          SearchParams.new(%{
            "wo_date_after" => Timex.shift(now, minutes: -1),
            "wo_date_before" => Timex.shift(now, minutes: 1)
          })
        ).entries

      assert found_workorder.id == wo_now.id
    end

    # to be replaced by paginator unit tests
    @tag :skip
    test "filters workorders sets timeout" do
      project = insert(:project)
      workflow = insert(:workflow, project: project)

      SearchParams.status_list()
      |> Enum.map(fn status ->
        insert_list(1_000, :workorder, workflow: workflow, state: status)
      end)

      try do
        Invocation.search_workorders(
          project,
          SearchParams.new(%{"status" => SearchParams.status_list()}),
          %{
            page: 1,
            page_size: 10,
            options: [timeout: 30]
          }
        )
      rescue
        e in [DBConnection.ConnectionError] ->
          assert e.message =~ "timeout"
      end
    end
  end

  describe "searching across workorders" do
    setup do
      project = insert(:project)

      dataclip =
        insert(:dataclip,
          body: %{
            "player" => "Sadio Mane",
            "date_of_birth" => "1992-04-10",
            "fav_color" => "vert foncé"
          },
          type: :global,
          project: project
        )

      %{workflow: workflow, trigger: trigger, job: job, snapshot: snapshot} =
        build_workflow(project: project, name: "chw-help")

      workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip,
          snapshot: snapshot
        )

      run =
        insert(:run,
          work_order: workorder,
          dataclip: dataclip,
          snapshot: snapshot,
          starting_trigger: trigger
        )

      {:ok, step} =
        Runs.start_step(run, %{
          "job_id" => job.id,
          "input_dataclip_id" => dataclip.id,
          "step_id" => Ecto.UUID.generate()
        })

      insert(:log_line,
        run: run,
        step: step,
        message: "Sadio Mane is playing for Senegal",
        timestamp: Timex.now()
      )

      insert(:log_line,
        run: run,
        step: step,
        message: "Bukayo Saka is playing for England",
        timestamp: Timex.now()
      )

      %{
        project: project,
        dataclip: dataclip,
        workorder: workorder,
        run: run,
        step: step
      }
    end

    @tag skip: "Ooops. We don't support this yet."
    test "search on UUIDs can find partial string matches at any point in the dataclip UUID",
         %{project: project, dataclip: dataclip} do
      assert [_found] =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => dataclip.id,
                   "search_fields" => ["id"]
                 })
               ).entries

      assert [_found] =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => String.slice(dataclip.id, 4, 3),
                   "search_fields" => ["id"]
                 })
               ).entries
    end

    test "search on UUIDs can find partial string matches at any point in the work_order UUID",
         %{project: project, workorder: workorder} do
      assert [_found] =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => workorder.id,
                   "search_fields" => ["id"]
                 })
               ).entries

      assert [_found] =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => String.slice(workorder.id, 4, 3),
                   "search_fields" => ["id"]
                 })
               ).entries
    end

    test "search on UUIDs can find partial string matches at any point in the run UUID",
         %{project: project, run: run} do
      assert [_found] =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => run.id,
                   "search_fields" => ["id"]
                 })
               ).entries

      assert [_found] =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => String.slice(run.id, 4, 3),
                   "search_fields" => ["id"]
                 })
               ).entries
    end

    test "search on UUIDs can find partial string matches at any point in the step UUID",
         %{project: project, step: step} do
      assert [_found] =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => step.id,
                   "search_fields" => ["id"]
                 })
               ).entries

      assert [_found] =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => String.slice(step.id, 7, 2),
                   "search_fields" => ["id"]
                 })
               ).entries
    end

    test "search on logs does NOT return 'stem' matches... only exact matches",
         %{project: project} do
      assert [] =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => "played",
                   "search_fields" => ["log"]
                 })
               ).entries

      assert [] =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => "playings",
                   "search_fields" => ["log"]
                 })
               ).entries
    end

    test "search on logs can find partial string matches at the start of words",
         %{project: project} do
      assert [_found] =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => "Buka",
                   "search_fields" => ["log"]
                 })
               ).entries
    end

    @tag skip: "Ooops. We don't support this yet."
    test "search on logs can find partial string matches at the end of words", %{
      project: project
    } do
      assert [_found] =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => "ngland",
                   "search_fields" => ["log"]
                 })
               ).entries
    end

    test "search on logs can find partial string matches across words", %{
      project: project
    } do
      assert [_found] =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => "Bukayo Sa",
                   "search_fields" => ["log"]
                 })
               ).entries
    end

    test "search on dataclips can find partial string matches at the start of keys",
         %{
           project: project
         } do
      assert [_found] =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => "date_of",
                   "search_fields" => ["body"]
                 })
               ).entries

      assert [_found] =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => "bir",
                   "search_fields" => ["body"]
                 })
               ).entries

      assert [] =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => "irth",
                   "search_fields" => ["body"]
                 })
               ).entries
    end

    test "search on dataclips can find partial string matches at the start of values",
         %{
           project: project
         } do
      assert [_found] =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => "vert",
                   "search_fields" => ["body"]
                 })
               ).entries

      assert [] =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => "ncé",
                   "search_fields" => ["body"]
                 })
               ).entries

      assert [_found] =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => "199",
                   "search_fields" => ["body"]
                 })
               ).entries
    end

    test "filters workorders by search term on body and/or run logs and/or workorder, run, or step ID",
         %{project: project, workorder: workorder, run: run, step: step} do
      assert Invocation.search_workorders(
               project,
               SearchParams.new(%{
                 "search_term" => "won't match anything",
                 "search_fields" => ["body", "log"]
               })
             ).entries == []

      assert [found_workorder] =
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => "senegal",
                   "search_fields" => ["body", "log"]
                 })
               ).entries

      assert found_workorder.id == workorder.id

      assert [] ==
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => "senegal",
                   "search_fields" => ["body"]
                 })
               ).entries

      assert [] ==
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => "liverpool",
                   "search_fields" => ["log"]
                 })
               ).entries

      # By ID
      assert [] ==
               Invocation.search_workorders(
                 project,
                 SearchParams.new(%{
                   "search_term" => "nonexistentid",
                   "search_fields" => ["id"]
                 })
               ).entries

      # Search by Workorder, Run, or Step IDs and their parts
      search_ids =
        [workorder.id, run.id, step.id]
        |> Enum.map(fn uuid ->
          [part | _t] = String.split(uuid, "-")
          [part, uuid]
        end)
        |> List.flatten()

      for search_id <- search_ids do
        assert [found_workorder] =
                 Invocation.search_workorders(
                   project,
                   SearchParams.new(%{
                     "search_term" => search_id,
                     "search_fields" =>
                       ["id"] ++
                         Enum.take(["body", "log"], Enum.random([0, 1, 2]))
                   })
                 ).entries

        assert found_workorder.id == workorder.id
      end
    end
  end

  describe "search_workorders with UNION queries" do
    setup do
      project = insert(:project)

      dataclips =
        insert_list(3, :dataclip,
          body: %{
            "search_term" => "findme",
            "body_only" => "unique_body_value",
            "date" => "2024-01-01"
          },
          type: :global,
          project: project
        )

      dataclip = hd(dataclips)

      %{workflow: workflow, trigger: trigger, job: job, snapshot: snapshot} =
        build_workflow(project: project)

      workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip,
          snapshot: snapshot
        )

      run =
        insert(:run,
          work_order: workorder,
          dataclip: dataclip,
          snapshot: snapshot,
          starting_trigger: trigger
        )

      {:ok, step} =
        Runs.start_step(run, %{
          "job_id" => job.id,
          "input_dataclip_id" => dataclip.id,
          "step_id" => Ecto.UUID.generate()
        })

      # Log lines contains the same "findme" term plus a log-only term
      insert_list(3, :log_line,
        run: run,
        step: step,
        message: "Processing findme with log_only_value",
        timestamp: Timex.now()
      )

      %{
        project: project,
        workorder: workorder,
        run: run,
        step: step,
        dataclip: dataclip
      }
    end

    test "deduplicates work orders matching both body AND log",
         %{project: project, workorder: workorder} do
      # Search for "findme" which appears in BOTH body and log
      # Body: "search_term" => "findme"
      # Log: "Processing findme with log_only_value"

      page =
        Invocation.search_workorders(
          project,
          SearchParams.new(%{
            "search_term" => "findme",
            "search_fields" => ["body", "log"]
          })
        )

      # Should return exactly one work order, not duplicates
      assert length(page.entries) == 1
      assert hd(page.entries).id == workorder.id
    end

    test "handles body-only, log-only, and body+log searches correctly",
         %{project: project, workorder: workorder} do
      # Body contains: "unique_body_value" (only in body, not in log)
      # Log contains: "log_only_value" (only in log, not in body)

      # Test 1: Body-only search finds the work order
      page =
        Invocation.search_workorders(
          project,
          SearchParams.new(%{
            "search_term" => "unique_body",
            "search_fields" => ["body"]
          })
        )

      assert length(page.entries) == 1
      assert hd(page.entries).id == workorder.id

      # Test 2: Log-only search finds the work order
      page =
        Invocation.search_workorders(
          project,
          SearchParams.new(%{
            "search_term" => "log_only",
            "search_fields" => ["log"]
          })
        )

      assert length(page.entries) == 1
      assert hd(page.entries).id == workorder.id

      # Test 3: Body+log search with body-only term finds it
      page =
        Invocation.search_workorders(
          project,
          SearchParams.new(%{
            "search_term" => "unique_body",
            "search_fields" => ["body", "log"]
          })
        )

      assert length(page.entries) == 1
      assert hd(page.entries).id == workorder.id

      # Test 4: Body+log search with log-only term finds it
      page =
        Invocation.search_workorders(
          project,
          SearchParams.new(%{
            "search_term" => "log_only",
            "search_fields" => ["body", "log"]
          })
        )

      assert length(page.entries) == 1
      assert hd(page.entries).id == workorder.id

      # Test 5: Body+log search with non-matching term finds nothing
      page =
        Invocation.search_workorders(
          project,
          SearchParams.new(%{
            "search_term" => "nonexistent",
            "search_fields" => ["body", "log"]
          })
        )

      assert page.entries == []
    end

    test "with ID search field works correctly",
         %{project: project, workorder: workorder} do
      # Test 1: Search by ID with body+log fields using the work order ID
      [id_part | _] = String.split(workorder.id, "-")

      page =
        Invocation.search_workorders(
          project,
          SearchParams.new(%{
            "search_term" => id_part,
            "search_fields" => ["id", "body", "log"]
          })
        )

      # Should find the work order by ID
      assert length(page.entries) == 1
      assert hd(page.entries).id == workorder.id

      # Test 2: Search by term that's in body AND log with ID field present
      # "findme" appears in both body and log
      page =
        Invocation.search_workorders(
          project,
          SearchParams.new(%{
            "search_term" => "findme",
            "search_fields" => ["id", "body", "log"]
          })
        )

      # Should find by body/log (ID won't match "findme")
      assert length(page.entries) == 1
      assert hd(page.entries).id == workorder.id

      # Test 3: Verify no duplicates when ID + body + log all enabled
      # and term matches both body and log (not ID)
      page =
        Invocation.search_workorders(
          project,
          SearchParams.new(%{
            "search_term" => "findme",
            "search_fields" => ["id", "body", "log"]
          })
        )

      # Should still return only one result (UNION deduplicates)
      assert length(page.entries) == 1
      assert hd(page.entries).id == workorder.id
    end

    test "preserves all work order associations and preloads",
         %{project: project} do
      [workorder] =
        Invocation.search_workorders(
          project,
          SearchParams.new(%{
            "search_term" => "findme",
            "search_fields" => ["body", "log"]
          })
        ).entries

      # Verify all expected associations are loaded
      assert Ecto.assoc_loaded?(workorder.dataclip)
      assert Ecto.assoc_loaded?(workorder.workflow)
      assert Ecto.assoc_loaded?(workorder.snapshot)
      assert Ecto.assoc_loaded?(workorder.runs)

      # Verify nested associations
      assert [loaded_run] = workorder.runs
      assert Ecto.assoc_loaded?(loaded_run.steps)
      assert [loaded_step] = loaded_run.steps
      assert Ecto.assoc_loaded?(loaded_step.job)
      assert Ecto.assoc_loaded?(loaded_step.input_dataclip)
      assert Ecto.assoc_loaded?(loaded_step.snapshot)
    end
  end

  describe "search_workorders by dataclip_name" do
    test "finds case-insensitive substring matches on workorder input dataclip name" do
      project = insert(:project)

      %{workflow: workflow, trigger: trigger, snapshot: snapshot} =
        build_workflow(project: project)

      dataclip = insert(:dataclip, project: project, name: "My Test Dataclip")

      workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip,
          snapshot: snapshot
        )

      for term <- ["test", "TEST", "clip"] do
        params =
          SearchParams.new(%{
            "search_term" => term,
            "search_fields" => ["dataclip_name"]
          })

        page = Invocation.search_workorders(project, params)
        assert Enum.any?(page.entries, &(&1.id == workorder.id))
      end
    end

    test "does not match when dataclip_name is not enabled" do
      project = insert(:project)

      %{workflow: workflow, trigger: trigger, snapshot: snapshot} =
        build_workflow(project: project)

      dataclip = insert(:dataclip, project: project, name: "Label Only")

      _workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip,
          snapshot: snapshot
        )

      params =
        SearchParams.new(%{
          "search_term" => "Label",
          "search_fields" => ["log"]
        })

      page = Invocation.search_workorders(project, params)
      assert length(page.entries) == 0
    end

    test "does not match unnamed workorder dataclip" do
      project = insert(:project)

      %{workflow: workflow, trigger: trigger, snapshot: snapshot} =
        build_workflow(project: project)

      dataclip = insert(:dataclip, project: project, name: nil)

      _workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip,
          snapshot: snapshot
        )

      params =
        SearchParams.new(%{
          "search_term" => "anything",
          "search_fields" => ["dataclip_name"]
        })

      page = Invocation.search_workorders(project, params)
      assert length(page.entries) == 0
    end

    test "matches wiped dataclip names (body/request wiped, name retained)" do
      project = insert(:project)

      %{workflow: workflow, trigger: trigger, snapshot: snapshot} =
        build_workflow(project: project)

      dataclip =
        insert(:dataclip,
          project: project,
          name: "Wiped Name",
          wiped_at: Timex.now()
        )

      workorder =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip,
          snapshot: snapshot
        )

      params =
        SearchParams.new(%{
          "search_term" => "Wiped",
          "search_fields" => ["dataclip_name"]
        })

      page = Invocation.search_workorders(project, params)
      assert Enum.any?(page.entries, &(&1.id == workorder.id))
    end
  end

  describe "step logs" do
    test "logs_for_step/1 returns an array of the logs for a given step" do
      step =
        insert(:step,
          log_lines: ["Hello", "I am a", "log"] |> Enum.map(&build_log_map/1)
        )

      log_lines = Invocation.logs_for_step(step)

      assert Enum.count(log_lines) == 3

      assert log_lines |> Enum.map(fn log_line -> log_line.message end) == [
               "Hello",
               "I am a",
               "log"
             ]
    end

    test "assemble_logs_for_step/1 returns a string representation of the logs for a step" do
      step =
        insert(:step,
          log_lines: ["Hello", "I am a", "log"] |> Enum.map(&build_log_map/1)
        )

      log_string = Invocation.assemble_logs_for_step(step)

      assert log_string == "Hello\nI am a\nlog"
    end

    test "assemble_logs_for_step/1 returns nil when given a nil step" do
      assert Invocation.assemble_logs_for_step(nil) == nil
    end

    defp build_log_map(message) do
      %{id: Ecto.UUID.generate(), message: message, timestamp: build(:timestamp)}
    end
  end

  describe "export_workorders/3" do
    setup do
      project = insert(:project)
      user = insert(:user)
      search_params = SearchParams.new(%{})

      {:ok, project: project, user: user, search_params: search_params}
    end

    test "initiates a work orders export successfully and logs the audit event",
         %{
           project: project,
           user: user,
           search_params: search_params
         } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        result =
          Lightning.Invocation.export_workorders(project, user, search_params)

        assert {:ok, %{audit: audit, project_file: project_file}} =
                 result

        assert audit.event == "requested"
        assert audit.item_type == "history_export"
        assert audit.actor_id == user.id
        assert audit.metadata == %{search_params: search_params}

        assert project_file.status == :enqueued
        assert project_file.type == :export
      end)
    end
  end

  defp assert_dataclips_list(expected, returned) do
    assert expected
           |> Enum.map(&format_listed/1)
           |> Enum.map(&Map.delete(&1, :project)) ==
             Enum.map(returned, &Map.delete(&1, :project))
  end

  defp format_listed(dataclip) do
    dataclip
    |> Map.put(:body, nil)
    |> Map.put(:request, nil)
  end
end
