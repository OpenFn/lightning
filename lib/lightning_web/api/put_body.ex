defmodule LightningWeb.API.PutBody do
  @moduledoc """
  What every create-or-replace `PUT /:id` route shares: the checks on its path
  id and body before the body reaches a changeset (error-format spec §7 item 8,
  §9.5, §9.6), and telling when its insert lost a race for the id. Other API
  routes use the path id and JSON object checks too.
  """
  alias LightningWeb.API.Errors
  alias LightningWeb.API.Problem

  @doc """
  Checks `body` against the keys the route accepts and the id in its path.

  `path_id` is the path's id, already cast as a UUID.

  Returns `{:error, problem}` with a 400 `malformed` problem when the body is
  not a JSON object. Otherwise returns `{:ok, entries}`, empty when the body
  passes: one `unknown_key` entry for each key outside `accepted`, and a
  `mismatch` entry when the body's `id` is not `path_id`.
  """
  @spec check(map(), Ecto.UUID.t(), [atom()]) ::
          {:ok, [Errors.entry()]} | {:error, Problem.t()}
  def check(body, path_id, accepted) do
    with :ok <- check_object(body) do
      unknown =
        (Map.keys(body) -- Enum.map(accepted, &Atom.to_string/1))
        |> Enum.sort()
        |> Enum.map(&Errors.entry([&1], {"is not accepted", code: :unknown_key}))

      {:ok, unknown ++ id_mismatch(body, path_id)}
    end
  end

  @doc """
  `:ok` when `body`, a request's body params, was a JSON object. Otherwise a
  400 `malformed` problem, for any route that takes an object (spec §9.5).
  Plug.Parsers puts any other JSON value under `"_json"`.
  """
  @spec check_object(map()) :: :ok | {:error, Problem.t()}
  def check_object(%{"_json" => _not_an_object}),
    do: {:error, Problem.new(:malformed)}

  def check_object(_body), do: :ok

  @doc """
  The path's id, written out as a UUID.

  Returns `{:error, :not_found}` for anything else, since an id that isn't a
  UUID names nothing (spec §4). `Ecto.UUID.cast/1` would also take any 16-byte
  string as a raw UUID, landing the request under an id it doesn't name.
  """
  @spec path_id(String.t()) :: {:ok, Ecto.UUID.t()} | {:error, :not_found}
  def path_id(id) do
    with {:ok, raw} <- Ecto.UUID.dump(id),
         {:ok, uuid} <- Ecto.UUID.load(raw) do
      {:ok, uuid}
    else
      :error -> {:error, :not_found}
    end
  end

  @doc """
  Whether an insert at the path's id failed because the id's row now exists,
  that is, another request created it after the route looked the id up.
  """
  @spec id_taken?(Ecto.Changeset.t()) :: boolean()
  def id_taken?(changeset) do
    changeset.errors
    |> Keyword.get_values(:id)
    |> Enum.any?(fn {_message, opts} -> opts[:constraint] == :unique end)
  end

  defp id_mismatch(%{"id" => body_id}, path_id) do
    if Ecto.UUID.cast(body_id) == {:ok, path_id},
      do: [],
      else: [
        Errors.entry(
          [:id],
          {"does not match the id in the path", code: :mismatch}
        )
      ]
  end

  defp id_mismatch(_body, _path_id), do: []
end
