defmodule LightningWeb.API.RunRetryController do
  @moduledoc """
  `POST /api/runs/:id/retries`: retries a run from one of its steps, as the
  run page's retry button does, for a person who may run the project's
  workflows.

  The new run goes on the same work order. Steps that don't depend on the one
  retried from are carried over rather than run again
  (`Lightning.WorkOrders.retry/3`).
  """
  use LightningWeb, :controller

  alias Lightning.Runs
  alias Lightning.WorkOrders
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.HistoryBody
  alias LightningWeb.API.Request
  alias LightningWeb.API.RunJSON
  alias LightningWeb.API.Target

  action_fallback FallbackController

  plug LightningWeb.Plugs.AuthorizeAction, {:history, :run_workflow}

  @wiped {"cannot retry run using a wiped dataclip", code: :dataclip_wiped}

  @doc """
  Creates a run on the run's work order, starting from `step_id`, and answers
  201 with it.

  A run whose workflow had been deleted before the request is 409
  `not_retryable`, and one whose workflow another request deletes while this one
  runs is 409 `concurrent_edit`, as starting a work order answers. A step
  that isn't in the run is 422 with a `not_found` entry at `#/step_id`, and
  one whose input has been wiped a `dataclip_wiped` entry. The run limits are
  asked last, 429 `too_many_runs` or 402 `exceeds_limit`.

  ## Examples

      POST /api/runs/a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d/retries
      {"step_id": "e5f6a7b8-..."}
  """
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def create(conn, _params) do
    body = conn.body_params

    with {:ok, run} <-
           Target.in_project_of(
             conn.assigns.scope,
             Request.param(conn, "id"),
             {:history, :run_workflow},
             &Runs.get_project_id/1,
             &Runs.get_for_project(&1, &2,
               include: [steps: :input_dataclip, work_order: :workflow]
             )
           ),
         :ok <- refuse_deleted(run.work_order.workflow),
         :ok <- Request.check_object(body),
         {:ok, step} <- step(run, body),
         :ok <-
           WorkOrders.limit_run_creation(run.work_order.workflow.project_id),
         {:ok, new_run} <- retry(run, step, conn.assigns.current_resource) do
      conn
      |> put_status(:created)
      |> put_view(json: RunJSON)
      |> render("created.json", run: new_run, conn: conn)
    end
  end

  defp refuse_deleted(%{deleted_at: nil}), do: :ok
  # A deleted workflow can't be restored, so `scheduled_for_deletion`'s "cancel
  # the deletion first" would send the caller looking for something that isn't
  # there. The run itself still reads, so it isn't 404 either.
  defp refuse_deleted(_workflow), do: {:error, :not_retryable}

  defp step(run, body) do
    unknown = Request.unknown_keys(body, [], [:step_id])

    {step, entries} =
      case body do
        %{"step_id" => step_id} when not is_nil(step_id) ->
          find_step(run, step_id)

        _missing_or_null ->
          {nil, [blank()]}
      end

    with :ok <- Errors.refuse(unknown ++ entries), do: {:ok, step}
  end

  defp find_step(run, step_id) do
    with {:ok, id} <- Request.id({["step_id"], step_id}),
         %{} = step <- Enum.find(run.steps, &(&1.id == id)) do
      if is_nil(step.input_dataclip.wiped_at),
        do: {step, []},
        else: {nil, [Errors.entry(["step_id"], @wiped)]}
    else
      {:error, {:invalid_id, _location}} ->
        {nil, HistoryBody.id_entries(%{"step_id" => step_id}, "step_id")}

      nil ->
        {nil,
         [
           Errors.entry(
             ["step_id"],
             {"is not a step of this run", code: :not_found}
           )
         ]}
    end
  end

  defp blank,
    do: Errors.entry(["step_id"], {"can't be blank", validation: :required})

  defp retry(run, step, user) do
    case WorkOrders.retry(run.id, step.id, created_by: user) do
      # Deleted after the lookup read it.
      {:error, :workflow_deleted} ->
        {:error, :concurrent_edit}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, Errors.problem(changeset, %{input_dataclip_id: :step_id})}

      retried ->
        retried
    end
  end
end
