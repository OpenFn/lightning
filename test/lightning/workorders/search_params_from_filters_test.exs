defmodule Lightning.WorkOrders.SearchParamsFromFiltersTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.Invocation
  alias Lightning.WorkOrders.SearchParams

  test "the list endpoint's filters narrow the History search as the list narrows its page" do
    workflow = insert(:workflow)
    project = workflow.project
    other_workflow = insert(:workflow, project: project)

    old =
      insert(:workorder,
        workflow: workflow,
        dataclip: build(:dataclip),
        state: :failed,
        inserted_at: ~U[2024-01-01 00:00:00.000000Z],
        updated_at: ~U[2024-01-01 00:00:00.000000Z]
      )

    new =
      insert(:workorder,
        workflow: workflow,
        dataclip: build(:dataclip),
        state: :success,
        inserted_at: ~U[2024-06-01 00:00:00.000000Z],
        updated_at: ~U[2024-06-01 00:00:00.000000Z]
      )

    other =
      insert(:workorder,
        workflow: other_workflow,
        dataclip: build(:dataclip),
        state: :failed,
        inserted_at: ~U[2024-03-01 00:00:00.000000Z],
        updated_at: ~U[2024-09-01 00:00:00.000000Z]
      )

    for {filters, expected} <- [
          {%{}, [old, new, other]},
          {%{id: [old.id, other.id]}, [old, other]},
          {%{id: []}, []},
          {%{workflow_id: workflow.id}, [old, new]},
          {%{state: ["failed"]}, [old, other]},
          {%{inserted_after: ~U[2024-02-01 00:00:00.000000Z]}, [new, other]},
          {%{inserted_before: ~U[2024-03-01 00:00:00.000000Z]}, [old, other]},
          {%{updated_after: ~U[2024-07-01 00:00:00.000000Z]}, [other]},
          {%{updated_before: ~U[2024-06-01 00:00:00.000000Z]}, [old, new]}
        ] do
      found =
        project
        |> Invocation.search_workorders_for_retry(
          SearchParams.from_filters(filters)
        )
        |> Enum.map(& &1.id)
        |> Enum.sort()

      assert found == expected |> Enum.map(& &1.id) |> Enum.sort(),
             "#{inspect(filters)} found the wrong work orders"
    end
  end

  test "the new filters survive the round trip through an export job's arguments" do
    params =
      SearchParams.from_filters(%{
        id: [Ecto.UUID.generate()],
        updated_after: ~U[2024-07-01 00:00:00.000000Z],
        updated_before: ~U[2024-08-01 00:00:00.000000Z]
      })

    assert {:ok, ^params} =
             params
             |> Jason.encode!()
             |> Jason.decode!()
             |> SearchParams.from_map()
  end
end
