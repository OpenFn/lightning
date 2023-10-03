defmodule Lightning.WorkOrders.Query do
  import Ecto.Query

  alias Lightning.Attempt

  # Create a copy of the WorkOrder state enum to use in the query, or else
  # we would need to unnecessarly join the workorders table just for casting.
  @workorder_state Ecto.ParameterizedType.init(Ecto.Enum,
                     values: Ecto.Enum.values(Lightning.WorkOrder, :state)
                   )

  @state_order ~w[
    started
    available
    claimed
    success
    failed
    killed
    crashed
  ]
  @doc """
  Query to calculate the current state of a workorder.

  It takes an Attempt, as the state is updated after each attempt is changed.
  """
  def state_for(%Attempt{} = attempt) do
    Attempt
    |> with_cte("attempt_ordering",
      as:
        fragment(
          "SELECT * FROM UNNEST(?::attempt_state[]) WITH ORDINALITY o(state, ord)",
          @state_order
        )
    )
    |> join(:inner, [a], o in "attempt_ordering", on: a.state == o.state)
    |> where([a, o], a.work_order_id == ^attempt.work_order_id)
    |> select(
      [a, o],
      type(
        fragment(
          """
          CASE ?
          WHEN 'available' THEN 'pending'
          WHEN 'claimed' THEN 'pending'
          WHEN 'started' THEN 'running'
          ELSE ?::varchar
          END
          """,
          a.state,
          o.state
        ),
        ^@workorder_state
      )
    )
    |> order_by([a, o], asc: o.ord)
    |> first()
  end
end
