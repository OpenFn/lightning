defmodule Lightning.WorkOrders.Query do
  @moduledoc """
  Query functions for the Lightning.WorkOrders module.
  """
  import Ecto.Query

  alias Lightning.Attempt

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

  It takes an Attempt, as the state is updated after each attempt is changed.

  The logic is as follows:

  - All _other_ Attempts that are not in a finished state are considered first.
  - The current Attempt is unioned onto the unfinished attempts with a null
    ordinality.
  - The attempts are ordered by state in the following order
    `started > available > claimed > null`
  - The attempt states are then mapped to the workorder state enum, so `available`
    and `claimed` are both mapped to `pending` and `started` is mapped to `running`

  > The `null` ordinality ensures that the current attempt is always last in the
  > ordering.
  """
  @spec state_for(Attempt.t()) :: Ecto.Query.t()
  def state_for(%Attempt{} = attempt) do
    in_progress_query =
      Attempt
      |> with_cte("attempt_ordering",
        as:
          fragment(
            "SELECT * FROM UNNEST(?::varchar[]) WITH ORDINALITY o(state, ord)",
            @unfinished_state_order
          )
      )
      |> join(:inner, [a], o in "attempt_ordering", on: a.state == o.state)
      |> where(
        [a],
        a.work_order_id == ^attempt.work_order_id and
          a.state in ^@unfinished_state_order and
          a.id != ^attempt.id
      )
      |> select([a, o], %{state: a.state, ord: o.ord})

    union_query =
      from(a in Attempt,
        where: a.id == ^attempt.id,
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
