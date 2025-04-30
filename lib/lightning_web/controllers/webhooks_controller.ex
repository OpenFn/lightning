defmodule LightningWeb.WebhooksController do
  use LightningWeb, :controller

  alias Lightning.Extensions.UsageLimiting.Action
  alias Lightning.Extensions.UsageLimiting.Context
  alias Lightning.Services.RateLimiter
  alias Lightning.Services.UsageLimiter
  alias Lightning.Workflows
  alias Lightning.WorkOrders

  plug :reject_unfetched when action in [:create]
  plug :check_rate when action in [:create]

  # Reject requests with unfetched body params, as they are not supported
  # See Plug.Parsers in Endpoint for more information.
  defp reject_unfetched(conn, _) do
    case conn.body_params do
      %Plug.Conn.Unfetched{} ->
        conn
        |> put_status(415)
        |> put_view(LightningWeb.ErrorView)
        |> render(:"415")
        |> halt()

      _ ->
        conn
    end
  end

  # Note: Plug.Parsers is called before the Router.
  def check_rate(conn, _opts) do
    with %Workflows.Trigger{enabled: true, workflow: %{project_id: project_id}} <-
           conn.assigns.trigger,
         :ok <- RateLimiter.limit_request(conn, %Context{project_id: project_id}) do
      conn
    else
      %Workflows.Trigger{enabled: false} ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          message:
            "Unable to process request, trigger is disabled. Enable it on OpenFn to allow requests to this endpoint."
        })
        |> halt()

      {:error, :too_many_requests, %{text: message}} ->
        conn
        |> put_status(:too_many_requests)
        |> put_resp_header("retry-after", "1")
        |> json(%{"error" => message})
        |> halt()

      _no_trigger_or_workflow ->
        conn
        |> put_status(:not_found)
        |> json(%{"error" => "Webhook not found"})
        |> halt()
    end
  end

  @spec check(Plug.Conn.t(), %{path: binary()}) :: Plug.Conn.t()
  def check(conn, _params) do
    put_status(conn, :ok)
    |> json(%{
      message:
        "OpenFn webhook trigger found. Make a POST request to execute this workflow."
    })
  end

  @spec create(Plug.Conn.t(), %{path: binary()}) :: Plug.Conn.t()
  def create(%{assigns: %{trigger: trigger}} = conn, _params) do
    %Workflows.Trigger{workflow: workflow} = trigger

    case check_skip_run_creation(workflow.project_id) do
      {:ok, without_run?} ->
        {:ok, work_order} =
          WorkOrders.create_for(trigger,
            workflow: workflow,
            dataclip: %{
              body: conn.body_params,
              request: build_request(conn),
              type: :http_request,
              project_id: workflow.project_id
            },
            without_run: without_run?
          )

        json(conn, %{work_order_id: work_order.id})

      {:error, reason, %{text: message}} ->
        status =
          if reason == :too_many_requests,
            do: :too_many_requests,
            else: :payment_required

        conn
        |> put_status(status)
        |> json(%{error: message})
    end
  end

  defp check_skip_run_creation(project_id) do
    case UsageLimiter.limit_action(
           %Action{type: :new_run},
           %Context{project_id: project_id}
         ) do
      :ok ->
        {:ok, false}

      {:error, :too_many_runs, _message} ->
        {:ok, true}

      error ->
        error
    end
  end

  defp build_request(%Plug.Conn{} = conn) do
    %{
      method: conn.method,
      path: conn.path_info,
      query_params: conn.query_params,
      headers: conn.req_headers |> Enum.into(%{})
    }
  end
end
