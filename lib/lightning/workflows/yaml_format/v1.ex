defmodule Lightning.Workflows.YamlFormat.V1 do
  @moduledoc """
  Lightning's legacy ("v1") YAML format — **parse-only**.

  v1 export was deleted in Phase 4 of the portability spec alignment work
  (issue #4718). The only v1 path that survives is the parser needed to
  keep importing legacy YAML transparently.

  Lightning has no server-side v1 YAML parser today: the provisioning
  controller accepts JSON, and YAML→JSON conversion happens in the browser
  (`assets/js/yaml/util.ts`). The parse functions here exist as stubs so the
  `Lightning.Workflows.YamlFormat` façade can dispatch consistently;
  filling them in is tracked separately under Phase 5 work.
  """

  @doc """
  Parse v1 workflow YAML.

  Lightning has no server-side v1 YAML parser today: the provisioning
  controller accepts JSON, and YAML→JSON conversion happens in the browser
  (`assets/js/yaml/util.ts`). Returns `{:error, :not_implemented}`.
  """
  @spec parse_workflow(binary()) :: {:ok, map()} | {:error, term()}
  def parse_workflow(_yaml_string) do
    not_implemented()
  end

  @doc """
  Parse v1 project YAML.

  See `parse_workflow/1` — same caveat. Returns `{:error, :not_implemented}`.
  """
  @spec parse_project(binary()) :: {:ok, map()} | {:error, term()}
  def parse_project(_yaml_string) do
    not_implemented()
  end

  # Indirection prevents Elixir's type inference from narrowing public
  # function return types to a single `{:error, :not_implemented}` literal,
  # which would mark every alternative match clause in callers as
  # "dead code" until Phase 5 fills these stubs in.
  @spec not_implemented() :: {:ok, any()} | {:error, term()}
  defp not_implemented do
    case :persistent_term.get({__MODULE__, :placeholder}, :unimplemented) do
      :unimplemented -> {:error, :not_implemented}
      other -> other
    end
  end
end
