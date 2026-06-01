defmodule Lightning.Invocation.DataclipSearchVectorWorkerTest do
  use Lightning.DataCase, async: false

  import Lightning.Factories

  alias Lightning.Invocation.DataclipSearchVectorWorker
  alias Lightning.Repo

  # Reads back the pending/searchable state of a dataclip's search_vector. The
  # dataclip body lives in jsonb and the vector is built from it with the
  # `english_nostop` config to match the read side (`Lightning.Invocation`).
  defp search_vector_state(id, term) do
    %{rows: [[is_null, matches]]} =
      Repo.query!(
        """
        SELECT search_vector IS NULL,
               COALESCE(
                 search_vector @@ to_tsquery('english_nostop', $2),
                 false
               )
        FROM dataclips WHERE id = $1::uuid
        """,
        [Ecto.UUID.dump!(id), term]
      )

    %{null?: is_null, matches?: matches}
  end

  defp search_vector_text(id) do
    %{rows: [[vector]]} =
      Repo.query!(
        "SELECT search_vector::text FROM dataclips WHERE id = $1::uuid",
        [Ecto.UUID.dump!(id)]
      )

    vector
  end

  describe "perform/1" do
    test "fills search_vector for pending dataclips so they become searchable" do
      dataclip =
        insert(:dataclip, body: %{"greeting" => "searchableword in body"})

      # The insert path no longer builds the vector, so it starts NULL.
      assert %{null?: true, matches?: false} =
               search_vector_state(dataclip.id, "searchableword")

      assert {:ok, 1} = perform_job(DataclipSearchVectorWorker, %{})

      assert %{null?: false, matches?: true} =
               search_vector_state(dataclip.id, "searchableword")
    end

    test "a NULL/wiped body becomes an empty vector that leaves the pending set" do
      dataclip = insert(:dataclip, body: %{"foo" => "bar"})

      # Mimic a wiped dataclip: body NULL, search_vector still pending.
      Repo.query!(
        "UPDATE dataclips SET body = NULL, search_vector = NULL WHERE id = $1::uuid",
        [Ecto.UUID.dump!(dataclip.id)]
      )

      assert {:ok, 1} = perform_job(DataclipSearchVectorWorker, %{})

      # Non-NULL empty vector: the row leaves the pending set (won't be retried
      # forever) and matches nothing.
      assert %{null?: false, matches?: false} =
               search_vector_state(dataclip.id, "bar")

      assert search_vector_text(dataclip.id) == ""
    end

    test "an oversized body becomes an empty vector without rolling back the batch" do
      normal = insert(:dataclip, body: %{"note" => "normalsearchableword"})

      # ~200k distinct words exceeds the 1MB tsvector limit;
      # safe_jsonb_to_tsvector swallows the program_limit_exceeded and returns
      # ''::tsvector rather than raising and aborting the whole batch.
      oversized_value =
        1..200_000
        |> Enum.map_join(" ", &"w#{&1}")

      oversized = insert(:dataclip, body: %{"data" => oversized_value})

      assert {:ok, 2} = perform_job(DataclipSearchVectorWorker, %{})

      # The normal row in the same batch still got indexed.
      assert %{null?: false, matches?: true} =
               search_vector_state(normal.id, "normalsearchableword")

      # The oversized row is set to a non-NULL empty vector so it leaves the
      # pending set, but matches nothing and the worker did not crash.
      assert %{null?: false} = search_vector_state(oversized.id, "w1")
      assert search_vector_text(oversized.id) == ""
    end

    test "drains all pending dataclips across a batch" do
      dataclips =
        for n <- 1..5 do
          insert(:dataclip, body: %{"n" => "draindataclip#{n}"})
        end

      for dataclip <- dataclips do
        assert %{null?: true} =
                 search_vector_state(dataclip.id, "draindataclip1")
      end

      assert {:ok, 5} = perform_job(DataclipSearchVectorWorker, %{})

      for dataclip <- dataclips do
        assert %{null?: false} =
                 search_vector_state(dataclip.id, "draindataclip1")
      end
    end

    test "does not snowball when the per-run budget is not exhausted" do
      for n <- 1..3, do: insert(:dataclip, body: %{"n" => "modest#{n}"})

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, 3} = perform_job(DataclipSearchVectorWorker, %{})

        refute_enqueued(worker: DataclipSearchVectorWorker)
      end)
    end

    test "is idempotent: a second run with nothing pending fills 0 and snowballs nothing" do
      for n <- 1..3, do: insert(:dataclip, body: %{"n" => "again#{n}"})

      assert {:ok, 3} = perform_job(DataclipSearchVectorWorker, %{})

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, 0} = perform_job(DataclipSearchVectorWorker, %{})

        refute_enqueued(worker: DataclipSearchVectorWorker)
      end)
    end
  end

  describe "snowball uniqueness" do
    # Guards the snowball chain: an executing job must be able to enqueue its
    # successor. Oban's default unique states include :executing, so a snowball
    # would otherwise match itself and the chain would die after one hop. The
    # worker restricts uniqueness to [:available, :scheduled] to avoid this.
    test "an executing snowball does not block enqueuing its successor" do
      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, running} =
          Oban.insert(
            Lightning.Oban,
            DataclipSearchVectorWorker.new(%{"trigger" => "snowball"})
          )

        # Mimic Oban marking the job as executing while perform/1 runs.
        from(j in Oban.Job, where: j.id == ^running.id)
        |> Repo.update_all(set: [state: "executing"])

        {:ok, successor} =
          Oban.insert(
            Lightning.Oban,
            DataclipSearchVectorWorker.new(%{"trigger" => "snowball"})
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
            DataclipSearchVectorWorker.new(%{"trigger" => "snowball"})
          )

        {:ok, second} =
          Oban.insert(
            Lightning.Oban,
            DataclipSearchVectorWorker.new(%{"trigger" => "snowball"})
          )

        assert second.conflict?
        assert second.id == first.id
      end)
    end
  end
end
