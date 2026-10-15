defmodule LightningWeb.API.PutBody do
  @moduledoc """
  The checks every create-or-replace `PUT /:id` route makes on its body before
  the body reaches a changeset (error-format spec §7 item 8, §9.5, §9.6).
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
  def check(%{"_json" => _not_an_object}, _path_id, _accepted),
    do: {:error, Problem.new(:malformed)}

  def check(body, path_id, accepted) do
    unknown =
      (Map.keys(body) -- Enum.map(accepted, &Atom.to_string/1))
      |> Enum.sort()
      |> Enum.map(&Errors.entry([&1], {"is not accepted", code: :unknown_key}))

    {:ok, unknown ++ id_mismatch(body, path_id)}
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
