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

  def call(conn, {:error, :not_found}),
    do: Problem.respond(conn, Problem.new(:not_found))

  def call(conn, {:error, :no_such_project}),
    do: Problem.respond(conn, Problem.new(:not_found))

  def call(conn, {:error, :no_standing}),
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

  def call(conn, {:error, :scheduled_for_deletion}),
    do: Problem.respond(conn, Problem.new(:scheduled_for_deletion))

  def call(conn, {:error, :id_taken}),
    do: Problem.respond(conn, Problem.new(:id_taken))

  def call(conn, {:error, :exceeds_limit}),
    do: Problem.respond(conn, Problem.new(:exceeds_limit))

  def call(conn, {:error, :not_related_to_project}) do
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
