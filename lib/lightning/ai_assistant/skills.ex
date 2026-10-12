defmodule Lightning.AiAssistant.Skills do
  @moduledoc """
  Skills the user can invoke in the global assistant with a slash command.

  These are Apollo's standard skills, so each name must match a
  `skills/<name>/SKILL.md` there; Apollo rejects any other name.

  `workflow` says which workflows a skill makes sense for: `"new"` ones not
  yet saved, or `"existing"` ones with steps and runs to look at.
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
      workflow: "new"
    },
    %{
      name: "diagnose",
      description: "Find out why a run failed, from its logs and data",
      workflow: "existing"
    },
    %{
      name: "qa",
      description: "Review this workflow for bugs and risky patterns",
      workflow: "existing"
    }
  ]

  @spec list() :: [skill()]
  def list, do: @skills

  @doc """
  The skill a message invokes: a known `/name` as its first token that fits
  the workflow being new or not, or nil.
  """
  @spec detect(String.t(), boolean()) :: String.t() | nil
  def detect("/" <> rest, new_workflow?) do
    name = rest |> String.split(~r/\s/, parts: 2) |> hd()
    workflow = if new_workflow?, do: "new", else: "existing"

    if Enum.any?(@skills, &(&1.name == name and &1.workflow == workflow)),
      do: name
  end

  def detect(_content, _new_workflow?), do: nil
end
