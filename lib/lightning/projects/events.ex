defmodule Lightning.Projects.Events do
  @moduledoc """
  Events for Projects changes.
  """
  defmodule ProjectCreated do
    @moduledoc false
    defstruct project: nil
  end

  defmodule ProjectDeleted do
    @moduledoc false
    defstruct project: nil
  end

  def project_created(project) do
    Lightning.broadcast(
      topic(),
      %ProjectCreated{project: project}
    )
  end

  def project_deleted(project) do
    Lightning.broadcast(
      topic(),
      %ProjectDeleted{project: project}
    )
  end

  def subscribe do
    Lightning.subscribe(topic())
  end

  defp topic, do: "projects_events:all"
end
