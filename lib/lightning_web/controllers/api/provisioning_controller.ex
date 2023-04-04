defmodule LightningWeb.API.ProvisioningController do
  use LightningWeb, :controller

  alias Lightning.Projects
  plug :accepts, ["json"]

  action_fallback LightningWeb.FallbackController

  def create(conn, params) do
    Projects.import_project(params, conn.assigns.current_user)
    |> case do
      {:error, operation, value, changes_so_far} ->
        IO.inspect({operation, value, changes_so_far},
          pretty: true,
          label: "error/4"
        )

        conn
        |> put_status(400)
        |> render("create.json", conn: conn, operation: operation, value: value)

      {:ok, _items} ->
        render(conn, "create.json", conn: conn)
    end
  end
end

defmodule LightningWeb.API.ProvisioningJSON do
  @moduledoc false
  # import LightningWeb.API.Helpers
  def render("create.json", %{conn: _conn, operation: operation, value: value}) do
    Map.new([
      {operation, flatten_errors(value)}
    ])
    |> IO.inspect()
  end

  def render("create.json", %{conn: _conn}) do
    %{}
  end

  defp flatten_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} ->
      msg
    end)
  end
end
