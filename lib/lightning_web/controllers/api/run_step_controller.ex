defmodule LightningWeb.API.RunStepController do
  @moduledoc """
  `GET /api/runs/:id/steps`: a run's steps, in the order they ran, for any
  member of the run's project. `job_id` narrows them to one job's. Not paged.
  """
  use LightningWeb, :controller

  alias Lightning.Runs
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Request
  alias LightningWeb.API.Target

  action_fallback FallbackController

  plug LightningWeb.Plugs.AuthorizeAction, {:history, :read_history}

  @doc """
  Lists the run's steps. A `job_id` that isn't a UUID is 400
  `invalid_parameter`, once the caller may read the run.

  ## Examples

      GET /api/runs/a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d/steps
      GET /api/runs/a1b2c3d4-.../steps?job_id=e5f6a7b8-...
  """
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def index(conn, params) do
    with {:ok, run} <-
           Target.in_project_of(
             conn.assigns.scope,
             Request.param(conn, "id"),
             {:history, :read_history},
             &Runs.get_project_id/1,
             &Runs.get_for_project(&1, &2, include: [:steps])
           ),
         {:ok, keep?} <- job_filter(conn, params) do
      steps =
        run.steps
        |> Enum.filter(keep?)
        |> Enum.sort_by(&{DateTime.to_unix(&1.inserted_at, :microsecond), &1.id})

      render(conn, "index.json", steps: steps, conn: conn)
    end
  end

  defp job_filter(conn, %{"job_id" => _}) do
    with {:ok, job_id} <- Request.id(Request.param(conn, "job_id")),
         do: {:ok, &(&1.job_id == job_id)}
  end

  defp job_filter(_conn, _params), do: {:ok, fn _step -> true end}
end
