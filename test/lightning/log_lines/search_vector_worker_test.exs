defmodule Lightning.LogLines.SearchVectorWorkerTest do
  use Lightning.DataCase, async: false

  import Lightning.Factories

  alias Lightning.LogLines.SearchVectorWorker
  alias Lightning.Repo
  alias Lightning.Runs

  setup do
    dataclip = insert(:dataclip)
    %{triggers: [trigger]} = workflow = insert(:simple_workflow)

    %{runs: [run]} =
      work_order_for(trigger, workflow: workflow, dataclip: dataclip)
      |> insert()

    %{run: run}
  end

  # Inserts a log line via the public API. With the synchronous trigger removed
  # this leaves `search_vector` NULL, which is exactly the pending state the
  # worker drains.
  defp append_log(run, message) do
    {:ok, log_line} =
      Runs.append_run_log(run, %{
        message: message,
        timestamp: DateTime.utc_now() |> DateTime.to_unix(:millisecond)
      })

    log_line
  end

  # Inserts a log line directly, bypassing the API, so we can stuff in an
  # oversized message that would blow past the 1MB tsvector limit. `search_vector`
  # is left NULL just like the regular insert path.
  defp insert_raw_log(run, message) do
    id = Ecto.UUID.generate()

    Repo.query!(
      """
      INSERT INTO log_lines (id, run_id, message, timestamp)
      VALUES ($1::uuid, $2::uuid, $3, now())
      """,
      [
        Ecto.UUID.dump!(id),
        Ecto.UUID.dump!(run.id),
        message
      ]
    )

    id
  end

  defp search_vector_state(id) do
    %{rows: [[is_null, matches]]} =
      Repo.query!(
        """
        SELECT search_vector IS NULL,
               COALESCE(search_vector @@ to_tsquery('english_nostop', 'logline'), false)
        FROM log_lines WHERE id = $1::uuid
        """,
        [Ecto.UUID.dump!(id)]
      )

    %{null?: is_null, matches?: matches}
  end

  describe "perform/1" do
    test "fills search_vector for pending log lines so they become searchable",
         %{run: run} do
      ids =
        for n <- 1..5 do
          append_log(run, "logline number #{n} doing work").id
        end

      # Freshly inserted lines start out unindexed (deferred computation).
      for id <- ids do
        assert %{null?: true, matches?: false} = search_vector_state(id)
      end

      assert {:ok, 5} = perform_job(SearchVectorWorker, %{})

      # After draining, every row has a populated, matching search_vector.
      for id <- ids do
        assert %{null?: false, matches?: true} = search_vector_state(id)
      end
    end

    test "an oversized message becomes an empty vector without rolling back the batch",
         %{run: run} do
      normal_id = append_log(run, "logline a normal searchable entry").id

      # 200k distinct words exceeds the 1MB tsvector limit; safe_to_tsvector
      # swallows the program_limit_exceeded and returns ''::tsvector.
      oversized =
        1..200_000
        |> Enum.map_join(" ", &"w#{&1}")

      oversized_id = insert_raw_log(run, oversized)

      assert {:ok, filled} = perform_job(SearchVectorWorker, %{})
      assert filled == 2

      # The normal row in the same batch still got indexed.
      assert %{null?: false, matches?: true} = search_vector_state(normal_id)

      # The oversized row is set to a non-NULL empty vector (so it leaves the
      # pending set and is not retried forever) but matches nothing.
      assert %{null?: false, matches?: false} = search_vector_state(oversized_id)

      %{rows: [[vector]]} =
        Repo.query!(
          "SELECT search_vector::text FROM log_lines WHERE id = $1::uuid",
          [Ecto.UUID.dump!(oversized_id)]
        )

      assert vector == ""
    end

    test "does not snowball when the per-run budget is not exhausted", %{
      run: run
    } do
      for n <- 1..3, do: append_log(run, "logline modest backlog #{n}")

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, 3} = perform_job(SearchVectorWorker, %{})

        refute_enqueued(worker: SearchVectorWorker)
      end)
    end

    test "is idempotent: a second run with nothing pending fills 0 and snowballs nothing",
         %{run: run} do
      for n <- 1..3, do: append_log(run, "logline #{n}")

      assert {:ok, 3} = perform_job(SearchVectorWorker, %{})

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, 0} = perform_job(SearchVectorWorker, %{})

        refute_enqueued(worker: SearchVectorWorker)
      end)
    end
  end

  describe "snowball uniqueness" do
    # Regression: Oban's default unique states include :executing and :completed,
    # so a running snowball job (state :executing) matched *itself* when it tried
    # to enqueue its successor — the insert was silently deduped and the chain
    # died after one hop. The worker restricts uniqueness to the queued states so
    # an executing job can always enqueue the next link.
    test "an executing snowball does not block enqueuing its successor" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, running} =
          Oban.insert(
            Lightning.Oban,
            SearchVectorWorker.new(%{"trigger" => "snowball"})
          )

        # Mimic Oban marking the job as executing while perform/1 runs.
        from(j in Oban.Job, where: j.id == ^running.id)
        |> Repo.update_all(set: [state: "executing"])

        {:ok, successor} =
          Oban.insert(
            Lightning.Oban,
            SearchVectorWorker.new(%{"trigger" => "snowball"})
          )

        refute successor.conflict?
        refute successor.id == running.id
      end)
    end

    test "two queued snowballs are deduped to one" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, first} =
          Oban.insert(
            Lightning.Oban,
            SearchVectorWorker.new(%{"trigger" => "snowball"})
          )

        {:ok, second} =
          Oban.insert(
            Lightning.Oban,
            SearchVectorWorker.new(%{"trigger" => "snowball"})
          )

        assert second.conflict?
        assert second.id == first.id
      end)
    end
  end
end
