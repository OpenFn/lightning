defmodule LightningWeb.API.FallbackController do
  @moduledoc """
  Answers an API action's error result with a problem document. A controller
  that sets it as `action_fallback` returns refusals from its `with` and never
  picks a status itself. `LightningWeb.Plugs.AuthorizeAction` answers its
  refusals here too.

  Each result has its own clause, and there is deliberately no catch-all. A
  result with no clause raises, so it shows up as a 500 and gets a clause.
  `{:error, :unauthorized}` from `Permissions.can/4` has no clause either,
  because a refused permission is never a 401.
  """
  alias Lightning.Extensions.Message
  alias LightningWeb.API.Codes
  alias LightningWeb.API.Errors
  alias LightningWeb.API.Problem
  alias LightningWeb.Auth

  require Logger

  @not_a_uuid {"is not a UUID", validation: :cast, type: :binary_id}

  # action_fallback hands the action's result to init/1, then to call/2.
  @doc false
  @spec init(term()) :: term()
  def init(result), do: result

  @spec call(Plug.Conn.t(), term()) :: Plug.Conn.t()
  def call(conn, {:error, %Ecto.Changeset{} = changeset}),
    do: Problem.respond(conn, Errors.problem(changeset))

  def call(conn, {:error, %Problem{} = problem}),
    do: Problem.respond(conn, problem)

  def call(conn, {:error, reason})
      when reason in [
             :not_found,
             :no_such_project,
             :workflow_deleted
           ],
      do: Problem.respond(conn, Problem.new(:not_found))

  def call(conn, {:error, {:invalid_id, body_keys}}) when is_list(body_keys),
    do: refuse_id(conn, :invalid, body_keys)

  def call(conn, {:error, {:invalid_id, path_or_parameter}}),
    do: refuse_id(conn, :invalid_parameter, path_or_parameter)

  def call(conn, {:error, reason}) when reason in [:forbidden, :no_standing],
    do: Problem.respond(conn, Problem.new(:forbidden))

  def call(conn, {:error, {:insufficient_scope, grant}}) do
    problem =
      Problem.new(:insufficient_scope,
        headers: [Auth.insufficient_scope_challenge(grant)]
      )

    Problem.respond(conn, problem)
  end

  def call(conn, {:error, reason})
      when reason in [
             :scheduled_for_deletion,
             :being_edited,
             :concurrent_edit,
             :id_taken,
             :in_use,
             :ambiguous_name,
             :exceeds_limit
           ],
      do: Problem.respond(conn, Problem.new(reason))

  def call(conn, {:error, :not_ready}),
    do: Problem.respond(conn, Problem.new(:not_ready, retry_after: 5))

  def call(conn, {:error, :unknown_project, %Message{}}),
    do: call(conn, {:error, :not_found})

  def call(conn, {:error, reason, %Message{}}),
    do: Problem.respond(conn, Problem.new(Codes.for_limiter(reason)))

  def call(conn, {:error, :audit_failed}) do
    Logger.error(
      "An API action could not write the audit events of a project change"
    )

    Problem.respond(conn, Problem.new(:internal))
  end

  def call(conn, {:error, :snapshot_failed}) do
    Logger.error("An API action could not save a workflow snapshot")
    Problem.respond(conn, Problem.new(:internal))
  end

  defp refuse_id(conn, code, location) do
    entry = Errors.entry(location, @not_a_uuid)
    Problem.respond(conn, Problem.new(code, errors: [entry]))
  end
end
