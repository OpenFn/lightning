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
        %{label: "cdp_query_api", selected: false},
        %{label: "pardot_api", selected: false},
        %{label: "cdp_profile_api", selected: false},
        %{label: "chatter_api", selected: false},
        %{label: "cdp_ingest_api", selected: false},
        %{label: "eclair_api", selected: false},
        %{label: "wave_api", selected: false},
        %{label: "api", selected: false},
        %{label: "custom_permissions", selected: false},
        %{label: "id", selected: false},
        %{label: "profile", selected: false},
        %{label: "email", selected: false},
        %{label: "address", selected: false},
        %{label: "phone", selected: false},
        %{label: "lightning", selected: false},
        %{label: "content", selected: false},
        %{label: "openid", selected: false},
        %{label: "full", selected: false},
        %{label: "visualforce", selected: false},
        %{label: "web", selected: false},
        %{label: "chatbot_api", selected: false},
        %{label: "user_registration_api", selected: false},
        %{label: "forgot_password", selected: false},
        %{label: "cdp_api", selected: false},
        %{label: "sfap_api", selected: false},
        %{label: "interaction_api", selected: false}
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
          label: data["label"],
          selected: data["selected"]
        }

      data ->
        %Option{label: data.label, selected: data.selected}
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
