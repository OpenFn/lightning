defmodule Lightning.DataclipScrubber do
  @moduledoc """
  Handles scrubbing of dataclips
  """

  import Ecto.Query

  alias Lightning.Credentials
  alias Lightning.Invocation.Step
  alias Lightning.Repo
  alias Lightning.RunStep
  alias Lightning.Scrubber

  @spec scrub_dataclip_body!(%{
          body: String.t() | nil,
          type: atom(),
          id: Ecto.UUID.t()
        }) :: String.t() | nil
  def scrub_dataclip_body!(%{body: nil}), do: nil

  def scrub_dataclip_body!(%{body: body} = dataclip) when is_binary(body) do
    if dataclip.type == :step_result do
      step_query = from s in Step, where: s.output_dataclip_id == ^dataclip.id
      scrub_body(body, Repo.one(step_query))
    else
      body
    end
  end

  defp scrub_body(body_str, %Step{
         id: step_id,
         started_at: started_at
       }) do
    step_id
    |> credentials_for_step(started_at)
    |> Repo.all()
    |> case do
      [] ->
        body_str

      credentials_with_env ->
        {_first_cred, project_env} = List.first(credentials_with_env)
        project_env = project_env || "main"

        credentials = Enum.map(credentials_with_env, fn {c, _env} -> c end)

        {:ok, scrubber} = Scrubber.start_link([])

        scrubber =
          credentials
          |> Enum.reduce(scrubber, fn credential, scrubber ->
            samples = Credentials.sensitive_values_for(credential, project_env)
            basic_auth = Credentials.basic_auth_for(credential, project_env)
            :ok = Scrubber.add_samples(scrubber, samples, basic_auth)
            scrubber
          end)

        Scrubber.scrub(scrubber, body_str)
    end
  end

  defp scrub_body(body_str, _step), do: body_str

  @doc """
  Returns an Ecto query for credentials (with project env) used in the same
  run or earlier steps.

  Uses a self-join on RunStep to leverage existing indexes.
  """
  def credentials_for_step(step_id, started_at) do
    from(r0 in RunStep,
      where: r0.step_id == ^step_id,
      join: r1 in RunStep,
      on: r1.run_id == r0.run_id,
      join: s in assoc(r1, :step),
      join: j in assoc(s, :job),
      join: c in assoc(j, :credential),
      join: r in assoc(r1, :run),
      join: wo in assoc(r, :work_order),
      join: w in assoc(wo, :workflow),
      join: p in assoc(w, :project),
      where: s.started_at <= ^started_at,
      select: {c, p.env},
      distinct: c.id
    )
  end
end
