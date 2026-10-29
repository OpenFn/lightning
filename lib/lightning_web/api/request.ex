defmodule LightningWeb.API.Request do
  @moduledoc """
  The checks on a request's ids and JSON body before the body reaches a
  changeset, and telling when a create-or-replace `PUT /:id` lost the race for
  its id.
  """
  alias Ecto.Changeset
  alias LightningWeb.API.Errors
  alias LightningWeb.API.Problem

  @mismatch {"does not match the id in the path", code: :mismatch}

  @doc """
  Checks `body` against the keys the route accepts and the id in its path.

  `id` is the id the URL names, already known to be a UUID.

  Returns `{:error, problem}` with a 400 `malformed` problem when the body is
  not a JSON object. Otherwise returns `{:ok, entries}`, empty when the body
  passes: one `unknown_key` entry for each key outside `accepted`, and a
  `mismatch` entry when the body's `id` names another.
  """
  @spec check(map(), Ecto.UUID.t(), [atom()]) ::
          {:ok, [Errors.entry()]} | {:error, Problem.t()}
  def check(body, id, accepted) do
    with :ok <- check_object(body) do
      {:ok, unknown_keys(body, [], accepted) ++ id_mismatch(body, id)}
    end
  end

  @doc """
  One `unknown_key` entry for each key of `object` outside `accepted`, in key
  order, each under `path`.
  """
  @spec unknown_keys(map(), [Errors.segment()], [atom()]) :: [Errors.entry()]
  def unknown_keys(object, path, accepted) do
    (Map.keys(object) -- Enum.map(accepted, &Atom.to_string/1))
    |> Enum.sort()
    |> Enum.map(
      &Errors.entry(path ++ [&1], {"is not accepted", code: :unknown_key})
    )
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

  @typedoc """
  A value the request sent, with where it sent it, such as
  `{{:path, "id"}, "a1b2..."}`. `param/2` reads one from a conn.
  """
  @type param :: {Errors.location(), term()}

  @doc """
  The value of the request's parameter `name`, with where it came from: the
  path, the query, or else the body.
  """
  @spec param(Plug.Conn.t(), String.t()) :: param()
  def param(conn, name) do
    cond do
      Map.has_key?(conn.path_params, name) ->
        {{:path, name}, conn.path_params[name]}

      Map.has_key?(conn.query_params, name) ->
        {{:parameter, name}, conn.query_params[name]}

      true ->
        {[name], conn.body_params[name]}
    end
  end

  @doc """
  The id in `param`, written out as a UUID.

  Returns `{:error, {:invalid_id, location}}` for anything else, naming where
  the request sent it. `Ecto.UUID.cast/1` would also take any 16-byte string as
  a raw UUID, landing the request under an id it doesn't name.
  """
  @spec id(param()) ::
          {:ok, Ecto.UUID.t()} | {:error, {:invalid_id, Errors.location()}}
  def id({location, value}) do
    case uuid(value) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, {:invalid_id, location}}
    end
  end

  defp uuid(value) do
    with {:ok, raw} <- Ecto.UUID.dump(value), do: Ecto.UUID.load(raw)
  end

  @doc """
  Whether an insert at the path's id failed because the id's row now exists,
  that is, another request created it after the route looked the id up.
  """
  @spec id_taken?(Changeset.t()) :: boolean()
  def id_taken?(changeset) do
    changeset.errors
    |> Keyword.get_values(:id)
    |> Enum.any?(fn {_message, opts} -> opts[:constraint] == :unique end)
  end

  @doc """
  `changeset` with a `mismatch` error on `field` when `body` names an id there
  other than `id`.
  """
  @spec validate_matches_path(Changeset.t(), map(), atom(), Ecto.UUID.t()) ::
          Changeset.t()
  def validate_matches_path(changeset, body, field, id) do
    if matches_path?(body, field, id) do
      changeset
    else
      {message, opts} = @mismatch
      Changeset.add_error(changeset, field, message, opts)
    end
  end

  defp id_mismatch(body, id) do
    if matches_path?(body, :id, id),
      do: [],
      else: [Errors.entry([:id], @mismatch)]
  end

  defp matches_path?(body, field, id) do
    case Map.fetch(body, Atom.to_string(field)) do
      {:ok, value} -> uuid(value) == uuid(id)
      :error -> true
    end
  end
end
