defmodule LightningWeb.API.PutRequest do
  @moduledoc """
  The rules every create-or-replace `PUT /:id` route shares.

  The id comes from the path, and a body that also carries a different one is
  refused, and so is a body key the route doesn't take. A refusal is a 422 of
  `{"errors": {field: [message]}}`. Messages never quote a submitted value, but
  an unaccepted key comes back as its own field.
  """
  import Ecto.Changeset

  @doc """
  Casts `body` against `types`, with the path's `id` as `:id`. `data` holds
  the defaults.

  Returns `{:ok, changeset}` for the route's own validations, to finish with
  `attrs/1`, or `{:error, :invalid, errors}` if the body isn't a JSON object or
  holds a key outside `types`.
  """
  @spec changeset(map(), String.t(), {map(), map()}) ::
          {:ok, Ecto.Changeset.t()} | {:error, :invalid, map()}
  def changeset(%{"_json" => _not_an_object}, _id, _schema),
    do: {:error, :invalid, %{body: ["must be a JSON object"]}}

  def changeset(body, id, {_data, types} = schema) do
    case Map.keys(body) -- Enum.map(Map.keys(types), &to_string/1) do
      [] ->
        {:ok, schema |> cast(body, Map.keys(types)) |> put_path_id(id)}

      keys ->
        {:error, :invalid, Map.new(keys, &{&1, ["is not accepted"]})}
    end
  end

  @spec attrs(Ecto.Changeset.t()) :: {:ok, map()} | {:error, :invalid, map()}
  def attrs(changeset) do
    case apply_action(changeset, :validate) do
      {:ok, attrs} -> {:ok, attrs}
      {:error, changeset} -> {:error, :invalid, flat_errors(changeset)}
    end
  end

  defp put_path_id(changeset, id) do
    case cast_uuid(id) do
      {:ok, id} ->
        changeset
        |> validate_change(:id, fn :id, body_id ->
          if body_id == id,
            do: [],
            else: [id: "does not match the id in the path"]
        end)
        |> put_change(:id, id)

      :error ->
        add_error(changeset, :id, "is not a UUID")
    end
  end

  @doc """
  Casts a written-out UUID. `Ecto.UUID.cast/1` also takes any 16-byte string
  as a raw UUID, so a 16-character path would land under an id other than the
  one it names.
  """
  @spec cast_uuid(term()) :: {:ok, Ecto.UUID.t()} | :error
  def cast_uuid(value) do
    with {:ok, raw} <- Ecto.UUID.dump(value), do: Ecto.UUID.load(raw)
  end

  @doc """
  Whether the write failed on `field`'s unique constraint. On `:id`, that means
  another request created the record after the route looked it up.
  """
  @spec unique_error?(Ecto.Changeset.t(), atom()) :: boolean()
  def unique_error?(changeset, field) do
    Enum.any?(changeset.errors, fn {error_field, {_message, opts}} ->
      error_field == field and opts[:constraint] == :unique
    end)
  end

  @doc """
  Returns a changeset's errors as one flat list of messages per field. An
  association's nested errors are merged into that field's list.
  """
  @spec flat_errors(Ecto.Changeset.t()) :: %{atom() => [String.t()]}
  def flat_errors(changeset) do
    changeset
    |> LightningWeb.CoreComponents.translate_errors()
    |> Map.new(fn {field, errors} -> {field, messages(errors)} end)
  end

  defp messages(errors) when is_map(errors),
    do: errors |> Map.values() |> messages()

  defp messages(errors) when is_list(errors),
    do: Enum.flat_map(errors, &messages/1)

  defp messages(message) when is_binary(message), do: [message]

  @spec render_errors(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def render_errors(conn, errors) do
    conn
    |> Plug.Conn.put_status(:unprocessable_entity)
    |> Phoenix.Controller.json(%{errors: errors})
  end
end
