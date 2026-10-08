defmodule Lightning.AiAssistant.Skills do
  @moduledoc """
  Skills the user can invoke in the global assistant with a slash command.

  These are Apollo's standard skills, so each name must match a
  `skills/<name>/SKILL.md` there; Apollo rejects any other name.
  """

  @type skill :: %{name: String.t(), description: String.t()}

  @skills [
    %{
      name: "design",
      description: "Work out what a workflow should do before building it"
    },
    %{
      name: "diagnose",
      description: "Find out why a run failed, from its logs and data"
    },
    %{
      name: "qa",
      description: "Review this workflow for bugs and risky patterns"
    }
  ]

  @spec list() :: [skill()]
  def list, do: @skills

  @doc """
  The skill a message invokes: a known `/name` as its first token, or nil.
  """
  @spec detect(String.t()) :: String.t() | nil
  def detect("/" <> rest) do
    name = rest |> String.split(~r/\s/, parts: 2) |> hd()

    if Enum.any?(@skills, &(&1.name == name)), do: name
  end

  def detect(_content), do: nil
end
