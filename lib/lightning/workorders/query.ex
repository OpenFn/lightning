defmodule Lightning.WorkOrders.Query do
  @moduledoc """
  Query functions for the Lightning.WorkOrders module.
  """
  import Ecto.Query

  alias Lightning.Run

  # Create a copy of the WorkOrder state enum to use in the query, or else
  # we would need to unnecessarly join the workorders table just for casting.
  # @workorder_state Ecto.ParameterizedType.init(Ecto.Enum,
  #                    values: Ecto.Enum.values(Lightning.WorkOrder, :state)
  #                  )

  @unfinished_state_order ~w[
    started
    available
    claimed
  ]

  @doc """
  Query to calculate the current state of a workorder.

  It takes a run, as the state is updated after each run is changed.

  The logic is as follows:

  - All _other_ Runs that are not in a finished state are considered first.
  - The current Run is unioned onto the unfinished runs with a null
    ordinality.
  - The runs are ordered by state in the following order
    `started > available > claimed > null`
  - The run states are then mapped to the workorder state enum, so `available`
    and `claimed` are both mapped to `pending` and `started` is mapped to `running`

  > The `null` ordinality ensures that the current run is always last in the
  > ordering.
  """
  @spec state_for(Run.t()) :: Ecto.Query.t()
  def state_for(%Run{} = run) do
    in_progress_query =
      Run
      |> with_cte("run_ordering",
        as:
          fragment(
            "SELECT * FROM UNNEST(?::varchar[]) WITH ORDINALITY o(state, ord)",
            @unfinished_state_order
          )
      )
      |> join(:inner, [a], o in "run_ordering", on: a.state == o.state)
      |> where(
        [a],
        a.work_order_id == ^run.work_order_id and
          a.state in ^@unfinished_state_order and
          a.id != ^run.id
      )
      |> select([a, o], %{state: a.state, ord: o.ord})

    union_query =
      from(a in Run,
        where: a.id == ^run.id,
        select: %{state: a.state, ord: nil},
        union: ^in_progress_query
      )

    from(u in subquery(union_query),
      order_by: [asc_nulls_last: u.ord],
      select: %{
        state:
          fragment(
            """
            CASE ?
            WHEN 'available' THEN 'pending'
            WHEN 'claimed' THEN 'pending'
            WHEN 'started' THEN 'running'
            ELSE ?
            END
            """,
            u.state,
            u.state
          )
      }
    )
    |> first()
  end
end
