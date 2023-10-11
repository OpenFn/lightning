defmodule Lightning.WorkOrders.Events do
  @moduledoc false

  defmodule AttemptCreated do
    @moduledoc false
    defstruct attempt: nil
  end

  defmodule AttemptUpdated do
    @moduledoc false
    defstruct attempt: nil
  end

  def attempt_created(project_id, attempt) do
    Lightning.broadcast(
      topic(project_id),
      %AttemptCreated{attempt: attempt}
    )
  end

  def subscribe(project_id) do
    Lightning.subscribe(topic(project_id))
  end

  defp topic(project_id), do: "project:#{project_id}"
end
