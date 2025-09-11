defmodule LightningWeb.ProfileLive.ExperimentalFeaturesComponent do
  @moduledoc """
  Component to manage experimental features on a User's profile
  """
  use LightningWeb, :live_component

  alias Lightning.Accounts

  defp form_changeset(user, params \\ %{}) do
    experimental_features =
      user.preferences |> Map.get("experimental_features", false)

    changeset =
      {%{experimental_features: experimental_features},
       %{experimental_features: :boolean}}
      |> Ecto.Changeset.cast(params, [:experimental_features])

    changeset
  end

  @impl true
  def update(%{user: user} = assigns, socket) do
    changeset = form_changeset(user)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(changeset: changeset)}
  end

  @impl true
  def handle_event("update_preferences", %{"preferences" => params}, socket) do
    user = socket.assigns.user

    changeset = form_changeset(user, params)

    with {:ok, data} <- Ecto.Changeset.apply_action(changeset, :validate),
         data <- Lightning.Utils.Maps.stringify_keys(data),
         {:ok, updated_user} <- Accounts.update_user_preferences(user, data) do
      {:noreply,
       socket
       |> assign(
         user: updated_user,
         changeset: changeset
       )
       |> put_flash(:info, "Experimental features updated successfully")}
    else
      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Failed to update experimental features. Please try again."
         )}
    end
  end
end
