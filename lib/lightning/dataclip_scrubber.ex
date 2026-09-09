defmodule Lightning.DataclipScrubber do
  @moduledoc """
  Handles scrubbing of dataclips
  """

  import Ecto.Query

  alias Lightning.Credentials
  alias Lightning.Invocation.Step
  alias Lightning.Repo
  alias Lightning.Run
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
        steps =
          from(s in Step, where: s.output_dataclip_id == ^dataclip.id)
          |> Repo.all()

        scrub_body(
          body,
          Enum.flat_map(
            steps,
            &(&1.id |> credentials_for_step(&1.started_at) |> Repo.all())
          ),
          Enum.flat_map(steps, &webhook_auth_methods_for_step(&1.id))
        )

      :http_request ->
        scrub_body(body, [], webhook_auth_methods_for_dataclip(dataclip.id))

      _ ->
        body
    end
  end

  @doc """
  Scrubs a batch of dataclip bodies, resolving what to scrub with a fixed
  number of queries.

  `scrub_dataclip_body!/1` looks up the step behind a dataclip, then its
  credentials, then its webhook auth methods - three queries per dataclip, two
  of them many-table joins. That is fine for the one dataclip a controller
  renders and an N+1 for the hundreds a page of the history export touches.

  Takes the same `%{id:, type:, body:}` maps as `scrub_dataclip_body!/1` and
  returns the scrubbed bodies keyed by dataclip id.
  """
  @spec scrub_dataclip_bodies!([
          %{body: String.t() | nil, type: atom(), id: Ecto.UUID.t()}
        ]) :: %{optional(Ecto.UUID.t()) => String.t() | nil}
  def scrub_dataclip_bodies!(dataclips) do
    context = build_context(dataclips)

    Map.new(dataclips, fn dataclip ->
      {dataclip.id, scrub_in_context(dataclip, context)}
    end)
  end

  defp build_context(dataclips) do
    ids_by_type = Enum.group_by(dataclips, & &1.type, & &1.id)

    steps_by_dataclip =
      steps_for_output_dataclips(Map.get(ids_by_type, :step_result, []))

    step_ids =
      steps_by_dataclip
      |> Enum.flat_map(fn {_dataclip_id, steps} -> Enum.map(steps, & &1.id) end)
      |> Enum.uniq()

    %{
      steps_by_dataclip: steps_by_dataclip,
      credentials_by_step: credentials_for_steps(step_ids),
      auth_methods_by_step: webhook_auth_methods_for_steps(step_ids),
      auth_methods_by_dataclip:
        webhook_auth_methods_for_dataclips(
          Map.get(ids_by_type, :http_request, [])
        )
    }
  end

  defp scrub_in_context(%{body: nil}, _context), do: nil

  defp scrub_in_context(%{body: body, type: :step_result, id: id}, context) do
    steps = Map.get(context.steps_by_dataclip, id, [])

    scrub_body(
      body,
      Enum.flat_map(steps, &Map.get(context.credentials_by_step, &1.id, [])),
      Enum.flat_map(steps, &Map.get(context.auth_methods_by_step, &1.id, []))
    )
  end

  defp scrub_in_context(%{body: body, type: :http_request, id: id}, context) do
    scrub_body(body, [], Map.get(context.auth_methods_by_dataclip, id, []))
  end

  defp scrub_in_context(%{body: body}, _context), do: body

  defp scrub_body(body_str, [], []), do: body_str

  defp scrub_body(body_str, credentials_with_env, webhook_auth_methods) do
    project_env =
      case credentials_with_env do
        [{_cred, env} | _] -> env || "main"
        [] -> "main"
      end

    credential_samples =
      Enum.map(credentials_with_env, fn {credential, _env} ->
        {Credentials.sensitive_values_for(credential, project_env),
         Credentials.basic_auth_for(credential, project_env)}
      end)

    auth_method_samples =
      Enum.map(webhook_auth_methods, fn auth_method ->
        {WebhookAuthMethod.sensitive_values_for(auth_method),
         WebhookAuthMethod.basic_auth_for(auth_method)}
      end)

    (credential_samples ++ auth_method_samples)
    |> Scrubber.build_state()
    |> Scrubber.scrub_string(body_str)
  end

  defp steps_for_output_dataclips([]), do: %{}

  defp steps_for_output_dataclips(dataclip_ids) do
    from(step in Step,
      where: step.output_dataclip_id in ^dataclip_ids,
      select: {step.output_dataclip_id, step}
    )
    |> Repo.all()
    |> group_by_key()
  end

  defp credentials_for_steps([]), do: %{}

  # `credentials_for_step/2` for many steps at once: each sibling step's cutoff
  # comes from its own target step rather than a bound value.
  defp credentials_for_steps(step_ids) do
    from(target_run_step in RunStep,
      where: target_run_step.step_id in ^step_ids,
      join: target_step in assoc(target_run_step, :step),
      join: run_step in RunStep,
      on: run_step.run_id == target_run_step.run_id,
      join: step in assoc(run_step, :step),
      join: job in assoc(step, :job),
      join: credential in assoc(job, :credential),
      join: run in assoc(run_step, :run),
      join: work_order in assoc(run, :work_order),
      join: workflow in assoc(work_order, :workflow),
      join: project in assoc(workflow, :project),
      where: step.started_at <= target_step.started_at,
      select: {target_run_step.step_id, {credential, project.env}},
      distinct: [target_run_step.step_id, credential.id]
    )
    |> Repo.all()
    |> group_by_key()
  end

  defp webhook_auth_methods_for_steps([]), do: %{}

  defp webhook_auth_methods_for_steps(step_ids) do
    from(run_step in RunStep,
      where: run_step.step_id in ^step_ids,
      join: run in assoc(run_step, :run),
      join: work_order in assoc(run, :work_order),
      join: trigger in assoc(work_order, :trigger),
      join: auth_method in assoc(trigger, :webhook_auth_methods),
      select: {run_step.step_id, auth_method},
      distinct: [run_step.step_id, auth_method.id]
    )
    |> Repo.all()
    |> group_by_key()
  end

  defp webhook_auth_methods_for_dataclips([]), do: %{}

  defp webhook_auth_methods_for_dataclips(dataclip_ids) do
    from(work_order in WorkOrder,
      where: work_order.dataclip_id in ^dataclip_ids,
      join: trigger in assoc(work_order, :trigger),
      join: auth_method in assoc(trigger, :webhook_auth_methods),
      select: {work_order.dataclip_id, auth_method},
      distinct: [work_order.dataclip_id, auth_method.id]
    )
    |> Repo.all()
    |> group_by_key()
  end

  defp group_by_key(rows) do
    Enum.group_by(rows, fn {key, _value} -> key end, fn {_key, value} ->
      value
    end)
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
  Returns webhook auth methods for a run by traversing:
  run -> work_order -> trigger -> webhook_auth_methods
  """
  def webhook_auth_methods_for_run(run_id) do
    from(r in Run,
      where: r.id == ^run_id,
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
