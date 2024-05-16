defmodule Lightning.DataclipScrubber do
  @moduledoc """
  Handles scrubbing of dataclips
  """

  import Ecto.Query

  alias Lightning.Credentials
  alias Lightning.Invocation.Dataclip
  alias Lightning.Invocation.Step
  alias Lightning.Repo
  alias Lightning.RunStep
  alias Lightning.Scrubber

  @spec scrub_dataclip_body!(Dataclip.t()) :: String.t()
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
    run_step =
      from(as in RunStep,
        where: as.step_id == ^step_id,
        select: as.run_id
      )

    from(as in RunStep,
      join: s in assoc(as, :step),
      join: j in assoc(s, :job),
      join: c in assoc(j, :credential),
      where: as.run_id in subquery(run_step),
      where: s.started_at <= ^started_at,
      select: c
    )
    |> Repo.all()
    |> case do
      [] ->
        body_str

      credentials ->
        {:ok, scrubber} = Scrubber.start_link([])

        credentials
        |> Enum.reduce(scrubber, fn credential, scrubber ->
          samples = Credentials.sensitive_values_for(credential)
          basic_auth = Credentials.basic_auth_for(credential)
          :ok = Scrubber.add_samples(scrubber, samples, basic_auth)
          scrubber
        end)
        |> Scrubber.scrub(body_str)
    end
  end

  defp scrub_body(body_str, _step), do: body_str
end
