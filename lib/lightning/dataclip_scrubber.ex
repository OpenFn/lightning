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
  alias Lightning.Workflows.WebhookAuthMethod
  alias Lightning.WorkOrder

  @spec scrub_dataclip_body!(%{
          body: String.t() | nil,
          type: atom(),
          id: Ecto.UUID.t()
        }) :: String.t() | nil
  def scrub_dataclip_body!(%{body: nil}), do: nil

  def scrub_dataclip_body!(%{body: body} = dataclip) when is_binary(body) do
    case dataclip.type do
      :step_result ->
        step_query = from s in Step, where: s.output_dataclip_id == ^dataclip.id
        scrub_body(body, Repo.one(step_query))

      :http_request ->
        scrub_http_request(body, dataclip.id)

      _ ->
        body
    end
  end

  defp scrub_body(body_str, %Step{id: step_id, started_at: started_at}) do
    credentials_with_env =
      step_id
      |> credentials_for_step(started_at)
      |> Repo.all()

    webhook_auth_methods = webhook_auth_methods_for_step(step_id)

    if Enum.empty?(credentials_with_env) and Enum.empty?(webhook_auth_methods) do
      body_str
    else
      project_env =
        case credentials_with_env do
          [{_cred, env} | _] -> env || "main"
          [] -> "main"
        end

      credentials = Enum.map(credentials_with_env, fn {c, _env} -> c end)

      {:ok, scrubber} = Scrubber.start_link([])

      scrubber =
        Enum.reduce(credentials, scrubber, fn credential, scrubber ->
          samples = Credentials.sensitive_values_for(credential, project_env)
          basic_auth = Credentials.basic_auth_for(credential, project_env)
          :ok = Scrubber.add_samples(scrubber, samples, basic_auth)
          scrubber
        end)

      scrubber =
        Enum.reduce(webhook_auth_methods, scrubber, fn auth_method, scrubber ->
          samples = WebhookAuthMethod.sensitive_values_for(auth_method)
          basic_auth = WebhookAuthMethod.basic_auth_for(auth_method)
          :ok = Scrubber.add_samples(scrubber, samples, basic_auth)
          scrubber
        end)

      Scrubber.scrub(scrubber, body_str)
    end
  end

  defp scrub_body(body_str, _step), do: body_str

  defp scrub_http_request(body_str, dataclip_id) do
    webhook_auth_methods = webhook_auth_methods_for_dataclip(dataclip_id)

    if Enum.empty?(webhook_auth_methods) do
      body_str
    else
      {:ok, scrubber} = Scrubber.start_link([])

      scrubber =
        Enum.reduce(webhook_auth_methods, scrubber, fn auth_method, scrubber ->
          samples = WebhookAuthMethod.sensitive_values_for(auth_method)
          basic_auth = WebhookAuthMethod.basic_auth_for(auth_method)
          :ok = Scrubber.add_samples(scrubber, samples, basic_auth)
          scrubber
        end)

      Scrubber.scrub(scrubber, body_str)
    end
  end

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

  @doc """
  Returns webhook auth methods for a step by traversing:
  step -> run_step -> run -> work_order -> trigger -> webhook_auth_methods
  """
  def webhook_auth_methods_for_step(step_id) do
    from(rs in RunStep,
      where: rs.step_id == ^step_id,
      join: r in assoc(rs, :run),
      join: wo in assoc(r, :work_order),
      join: t in assoc(wo, :trigger),
      join: wam in assoc(t, :webhook_auth_methods),
      select: wam,
      distinct: wam.id
    )
    |> Repo.all()
  end

  @doc """
  Returns webhook auth methods for an http_request dataclip by traversing:
  dataclip -> work_order -> trigger -> webhook_auth_methods
  """
  def webhook_auth_methods_for_dataclip(dataclip_id) do
    from(wo in WorkOrder,
      where: wo.dataclip_id == ^dataclip_id,
      join: t in assoc(wo, :trigger),
      join: wam in assoc(t, :webhook_auth_methods),
      select: wam,
      distinct: wam.id
    )
    |> Repo.all()
  end
end
