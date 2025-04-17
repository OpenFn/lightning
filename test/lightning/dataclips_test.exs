defmodule Lightning.DataclipsTest do
  use Lightning.DataCase

  alias Lightning.Dataclips

  describe "list_recent_for_job" do
    test "returns empty list if there are no input dataclips" do
      assert Dataclips.list_recent_for_job(Ecto.UUID.generate(), 5)
    end

    test "returns latest dataclips with body for a job and up to a limit of dataclips" do
      begin = DateTime.utc_now()

      %{jobs: [job1, job2 | _rest]} = insert(:complex_workflow)

      insert(:step,
        input_dataclip:
          build(:dataclip, body: %{"field" => "value"}, inserted_at: begin),
        job: job2
      )

      dataclips =
        Enum.map(1..6, fn i ->
          dataclip =
            insert(:dataclip,
              body: %{"foo#{i}" => "bar#{i}"},
              inserted_at: DateTime.add(begin, i, :millisecond)
            )
            |> Map.delete(:project)

          insert(:step, input_dataclip: dataclip, job: job1)

          assert dataclip.body == %{"foo#{i}" => "bar#{i}"}

          dataclip
        end)
        |> Enum.drop(1)
        |> Enum.sort_by(& &1.inserted_at, :desc)

      assert ^dataclips =
               Dataclips.list_recent_for_job(job1.id, 5)
               |> Enum.map(&Map.delete(&1, :project))
    end

    test "filters out wiped dataclips" do
      begin = DateTime.utc_now()

      %{jobs: [job1 | _rest]} = insert(:simple_workflow)

      insert(:step,
        input_dataclip:
          build(:dataclip,
            body: nil,
            inserted_at: begin,
            wiped_at: DateTime.utc_now()
          ),
        job: job1
      )

      dataclips =
        Enum.map(1..5, fn i ->
          dataclip =
            insert(:dataclip,
              body: %{"foo#{i}" => "bar#{i}"},
              inserted_at: DateTime.add(begin, i, :millisecond)
            )
            |> Map.delete(:project)

          insert(:step, input_dataclip: dataclip, job: job1)

          assert dataclip.body == %{"foo#{i}" => "bar#{i}"}

          dataclip
        end)
        |> Enum.sort_by(& &1.inserted_at, :desc)

      assert ^dataclips =
               Dataclips.list_recent_for_job(job1.id, 5)
               |> Enum.map(&Map.delete(&1, :project))
    end
  end
end
