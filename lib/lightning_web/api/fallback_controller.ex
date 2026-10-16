defmodule LightningWeb.API.FallbackController do
  @moduledoc """
  Answers an API action's error result with a problem document
  (error-format spec §8).

  Each result has its own clause, and there is deliberately no catch-all: a
  result with no clause raises, so it is logged as a 500 and gets a clause.
  `{:error, :unauthorized}` from `Permissions.can/4` has no clause either,
  because a refused permission is a 403 or a 404, never a 401 (plan D9).
  """
  alias LightningWeb.API.Challenge
  alias LightningWeb.API.Errors
  alias LightningWeb.API.Problem

  require Logger

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
      when reason in [:not_found, :no_such_project, :no_standing],
      do: Problem.respond(conn, Problem.new(:not_found))

  def call(conn, {:error, :forbidden}),
    do: Problem.respond(conn, Problem.new(:forbidden))

  def call(conn, {:error, {:insufficient_scope, grant}}) do
    problem =
      Problem.new(:insufficient_scope,
        headers: [Challenge.insufficient_scope(grant)]
      )

    Problem.respond(conn, problem)
  end

  def call(conn, {:error, reason})
      when reason in [:scheduled_for_deletion, :id_taken, :in_use],
      do: Problem.respond(conn, Problem.new(reason))

  def call(conn, {:error, :exceeds_limit}),
    do: Problem.respond(conn, Problem.new(:exceeds_limit))

  # The usage limiter's message is written for the app's pages, so the API
  # leaves it out.
  def call(conn, {:error, :exceeds_limit, _message}),
    do: call(conn, {:error, :exceeds_limit})

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
end
