defmodule LightningWeb.CredentialLive.ScopeSelectionComponent do
  use LightningWeb, :live_component

  import Phoenix.HTML.Form

  alias LightningWeb.CredentialLive.Scope
  alias LightningWeb.CredentialLive.Scope.Option

  def render(assigns) do
    ~H"""
    <div id={@id}>
      <h3 class="text-base font-semibold leading-6 text-gray-900 pb-2">
        Pick the scopes to authorize
      </h3>

      <.form
        :let={f}
        for={@scopes_changeset}
        phx-change="checked"
        phx-target={@myself}
        id="scope-selection-form"
      >
        <div class="grid grid-cols-4 gap-1">
          <%= inputs_for f, :options, fn value -> %>
            <div class="form-check">
              <label class="form-check-label inline-block">
                <%= checkbox(value, :selected,
                  value: value.data.selected,
                  class:
                    "form-check-input appearance-none h-4 w-4 border border-gray-300 rounded-sm bg-white checked:bg-blue-600 checked:border-blue-600 focus:outline-none transition duration-200 mt-1 align-top bg-no-repeat bg-center bg-contain float-left cursor-pointer"
                ) %>
                <%= label(value, :label, value.data.label, class: "ml-1") %>
                <%= hidden_input(value, :label, value: value.data.label) %>
              </label>
            </div>
          <% end %>
        </div>
      </.form>
    </div>
    """
  end

  def update(%{id: id, parent_id: parent_id} = _params, socket) do
    {:ok, socket |> assign(id: id) |> assign(parent_id: parent_id)}
  end

  def mount(socket) do
    scope_options =
      [
        %{id: 1, label: "cdp_query_api", selected: false},
        %{id: 2, label: "pardot_api", selected: false},
        %{id: 3, label: "cdp_profile_api", selected: false},
        %{id: 4, label: "chatter_api", selected: false},
        %{id: 5, label: "cdp_ingest_api", selected: false},
        %{id: 6, label: "eclair_api", selected: false},
        %{id: 7, label: "wave_api", selected: false},
        %{id: 8, label: "api", selected: false},
        %{id: 9, label: "custom_permissions", selected: false},
        %{id: 10, label: "id", selected: false},
        %{id: 11, label: "profile", selected: false},
        %{id: 12, label: "email", selected: false},
        %{id: 13, label: "address", selected: false},
        %{id: 14, label: "phone", selected: false},
        %{id: 15, label: "lightning", selected: false},
        %{id: 16, label: "content", selected: false},
        %{id: 17, label: "openid", selected: false},
        %{id: 18, label: "full", selected: false},
        %{id: 19, label: "visualforce", selected: false},
        %{id: 20, label: "web", selected: false},
        %{id: 21, label: "chatbot_api", selected: false},
        %{id: 22, label: "user_registration_api", selected: false},
        %{id: 23, label: "forgot_password", selected: false},
        %{id: 24, label: "cdp_api", selected: false},
        %{id: 25, label: "sfap_api", selected: false},
        %{id: 26, label: "interaction_api", selected: false}
      ]
      |> build_options()

    {:ok,
     socket
     |> assign(:scopes_changeset, build_changeset(scope_options))
     |> assign(:options, scope_options)}
  end

  defp build_options(options) do
    Enum.map(options, fn
      {_idx, data} ->
        %Option{
          id: data["id"],
          label: data["label"],
          selected: data["selected"]
        }

      data ->
        %Option{id: data.id, label: data.label, selected: data.selected}
    end)
  end

  defp build_changeset(options) do
    %Scope{}
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_embed(:options, options)
  end

  def handle_event("checked", %{"scope" => %{"options" => values}}, socket) do
    # Parse the form data and update the selected status
    updated_options =
      Enum.map(socket.assigns.options, fn option ->
        new_selected =
          case values["#{option.id - 1}"] do
            %{"selected" => "true"} -> true
            _ -> false
          end

        %{option | selected: new_selected}
      end)

    selected_scopes =
      updated_options |> Enum.filter(& &1.selected) |> Enum.map(& &1.label)

    send_update(LightningWeb.CredentialLive.OauthComponent,
      id: socket.assigns.parent_id,
      scopes: selected_scopes
    )

    updated_changeset = build_changeset(updated_options)

    {:noreply,
     assign(socket,
       scopes_changeset: updated_changeset,
       options: updated_options
     )}
  end

  # defp update_option(options, id, selected) do
  #   Enum.map(options, fn option ->
  #     if option.id == id, do: %{option | selected: selected}, else: option
  #   end)
  # end
end
