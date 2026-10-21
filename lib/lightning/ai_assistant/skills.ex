defmodule Lightning.AiAssistant.Skills do
  @moduledoc """
  Skills the user can invoke in the global assistant with a slash command.

  These are Apollo's standard skills, so each name must match a
  `skills/<name>/SKILL.md` there with no `metadata.agent`; Apollo rejects
  any other name.

  `workflow` says which workflows a skill makes sense for: `"any"`, or only
  `"existing"` ones, saved with steps and runs to look at.
  """

  @type skill :: %{
          name: String.t(),
          description: String.t(),
          workflow: String.t()
        }

  @skills [
    %{
      name: "design",
      description: "Work out what a workflow should do before building it",
      workflow: "any"
    },
    %{
      name: "diagnose",
      description: "Find out why a run failed, from its logs and data",
      workflow: "existing"
    },
    %{
      name: "qa",
      description: "Review this workflow and list what should change",
      workflow: "existing"
    }
  ]

  @spec list() :: [skill()]
  def list, do: @skills

  @doc """
  The skill a message invokes: a known `/name` as its first token, or nil.
  A skill for existing workflows does not count on a new one.
  """
  @spec detect(String.t(), boolean()) :: String.t() | nil
  def detect("/" <> rest, new_workflow?) do
    name = rest |> String.split(~r/\s/, parts: 2) |> hd()

    if Enum.any?(@skills, &(&1.name == name and fits?(&1, new_workflow?))),
      do: name
  end

  def detect(_content, _new_workflow?), do: nil

  defp fits?(%{workflow: "existing"}, true = _new_workflow?), do: false
  defp fits?(_skill, _new_workflow?), do: true
end
