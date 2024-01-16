defmodule LightningWeb.AuthProvidersLive.FormComponent do
  @moduledoc """
  Form Component for working with a single Job

  A Job's `adaptor` field is a combination of the module name and the version.
  It's formatted as an NPM style string.

  The form allows the user to select a module by name and then it's version,
  while the version dropdown itself references `adaptor` directly.

  Meaning the `adaptor_name` dropdown and assigns value is not persisted.
  """
  use LightningWeb, :live_component

  import LightningWeb.Components.Form

  alias Lightning.AuthProviders
  alias Lightning.AuthProviders.AuthConfigForm

  @impl true
  def update(
        %{auth_provider: auth_provider, id: id, redirect_host: redirect_host},
        socket
      ) do
    form_model = %{
      AuthConfigForm.from_auth_config(auth_provider)
      | redirect_host: redirect_host,
        redirect_path_func: fn name ->
          Routes.oidc_path(socket, :new, name || "")
        end
    }

    changeset = AuthConfigForm.change(form_model, %{})

    {:ok,
     socket
     |> assign(
       auth_provider: auth_provider,
       form_model: form_model,
       changeset: changeset,
       id: id,
       test_state: if(changeset.valid?, do: :unknown, else: nil)
     )}
  end

  @impl true
  def handle_event(
        "validate",
        %{"auth_provider" => auth_provider_params},
        socket
      ) do
    changeset =
      AuthConfigForm.change(socket.assigns.form_model, auth_provider_params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(
       changeset: changeset,
       test_state: if(changeset.valid?, do: :unknown, else: nil)
     )}
  end

  @impl true
  def handle_event("save", %{"auth_provider" => auth_provider_params}, socket) do
    attrs =
      AuthConfigForm.change(socket.assigns.form_model, auth_provider_params)
      |> Ecto.Changeset.apply_changes()
      |> Map.from_struct()

    case socket.assigns.id do
      :new ->
        AuthProviders.create(attrs)
        |> case do
          {:ok, model} ->
            {:noreply,
             socket
             |> assign(auth_provider: model)
             |> put_flash(:info, "Authentication Provider created.")
             |> push_redirect(
               to: Routes.auth_providers_index_path(socket, :edit)
             )}

          {:error, %Ecto.Changeset{}} ->
            {:noreply, socket |> put_flash(:error, "Something went wrong.")}
        end

      _ ->
        AuthProviders.update(socket.assigns.auth_provider, attrs)
        |> case do
          {:ok, model} ->
            {:noreply,
             socket
             |> assign(auth_provider: model)
             |> put_flash(:info, "Authentication Provider updated.")}

          {:error, %Ecto.Changeset{}} ->
            {:noreply, socket |> put_flash(:error, "Something went wrong.")}
        end
    end
  end

  @impl true
  def handle_event("test", _params, socket) do
    changeset =
      AuthConfigForm.validate_provider(socket.assigns.changeset)
      |> Map.put(:action, :validate)

    if changeset.valid? do
      {:noreply,
       socket
       |> assign(changeset: changeset, test_state: :success)}
    else
      {error_message, _} = changeset.errors[:discovery_url]

      {:noreply,
       socket
       |> assign(changeset: changeset, test_state: :failed)
       |> put_flash(:error, error_message)}
    end
  end

  @impl true
  def handle_event("disable", _params, socket) do
    AuthProviders.remove_handler(socket.assigns.auth_provider.name)
    AuthProviders.delete!(socket.assigns.auth_provider)

    {:noreply,
     socket
     |> put_flash(:info, "Authentication Provider removed")
     |> push_redirect(to: Routes.auth_providers_index_path(socket, :new))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={"project-#{@id}"}>
      <.form
        :let={f}
        as={:auth_provider}
        for={@changeset}
        id="auth-provider-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <div class="grid grid-cols-6 gap-6">
          <div class="col-span-3">
            <div class="grid grid-flow-row auto-rows-max gap-4">
              <div>
                <.text_field form={f} field={:name}>
                  <span class="text-xs text-secondary-500">
                    The name of the provider, used in the redirect URI.
                  </span>
                </.text_field>
              </div>
              <div>
                <.text_field form={f} field={:discovery_url} label="Discovery URL">
                  <span class="text-xs text-secondary-500">
                    The URL to the <code>.well-known</code> endpoint.
                  </span>
                </.text_field>
              </div>
              <div>
                <.text_field form={f} field={:client_id} label="Client ID" />
              </div>
              <div>
                <.password_field
                  form={f}
                  id={:client_secret}
                  value={Phoenix.HTML.Form.input_value(f, :client_secret)}
                  label="Client Secret"
                  required
                />
              </div>
              <div>
                <.text_field form={f} field={:redirect_host} label="Redirect Host" />
              </div>
            </div>
            <div class="hidden sm:block mt-4" aria-hidden="true">
              <div class="border-t border-secondary-200"></div>
            </div>
            <div class="mt-4">
              <div class="flex">
                <div class="flex-none">
                  <.submit_button
                    phx-disable-with="Saving"
                    disabled={!@changeset.valid?}
                  >
                    Save
                  </.submit_button>
                </div>
                <div class="grow"></div>
                <div class="flex-none">
                  <.test_button state={@test_state} myself={@myself} />
                </div>
              </div>
            </div>
          </div>
          <div class="col-span-3">
            <div class="flex flex-col h-full">
              <div class="flex-none text-sm text-secondary-700">
                <p>
                  Allows users with existing accounts to login with an external
                  OpenID Connect account that matches their email address.
                </p>
                <p class="mt-2">
                  In order to make things easier we rely on the providers well-known
                  file to determine all the different endpoints for authentication
                  and retrieving the user information.

                  Documentation on Google's OpenID Connect support and it's well-known
                  file see
                  <a
                    href="https://developers.google.com/identity/protocols/oauth2/openid-connect#discovery"
                    class="text-blue-500"
                    target="_blank"
                  >
                    here &raquo;
                  </a>
                </p>
              </div>

              <div class="flex-none hidden sm:block mt-4" aria-hidden="true">
                <div class="border-t border-secondary-200"></div>
              </div>

              <div class="flex-none mt-4">
                <div class="font-medium text-sm text-secondary-700">
                  Redirect URI
                </div>

                <%= if @changeset.valid? do %>
                  <div
                    id="redirect-uri-preview"
                    class="font-mono border rounded-md mt-4 p-2 text-secondary-700 bg-gray-200 border-slate-300 shadow-sm"
                  >
                    <%= Phoenix.HTML.Form.input_value(f, :redirect_uri) %>
                  </div>
                <% else %>
                  <div
                    id="redirect-uri-preview"
                    class="font-mono border rounded-md mt-4 p-2 text-gray-400 bg-gray-200 border-slate-300 shadow-sm cursor-not-allowed"
                  >
                    <%= Phoenix.HTML.Form.input_value(f, :redirect_host) %>&hellip;
                  </div>
                <% end %>
                <p class="mt-2 text-sm text-secondary-700">
                  Ensure your provider has this redirect URI set.
                  For more information see
                  <a
                    href="https://developers.google.com/identity/protocols/oauth2/openid-connect#setredirecturi"
                    class="text-blue-500"
                    target="_blank"
                  >
                    here &raquo;
                  </a>
                </p>
              </div>
              <%= if @auth_provider.id != nil do %>
                <div class="grow"></div>
                <div class="flex-none mt-4">
                  <div class="font-medium text-sm text-secondary-700">
                    Remove
                  </div>
                  <p class="my-2 text-sm text-secondary-700">
                    Deletes the Authentication Configuration, and disables
                    external authentication for Lightning.
                  </p>

                  <Common.button color="red" phx-click="disable" phx-target={@myself}>
                    <div class="h-full">
                      <Heroicons.trash class="h-4 w-4 inline-block" />
                      <span class="inline-block align-middle">Remove</span>
                    </div>
                  </Common.button>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </.form>
      <.live_info_block flash={@flash} myself={@myself} />
      <.live_error_block flash={@flash} myself={@myself} />
    </div>
    """
  end

  defp test_button(assigns) do
    ~H"""
    <%= case @state do %>
      <% :failed -> %>
        <Common.button color="red" id="test-button">
          <div class="h-full -ml-1">
            <Heroicons.x_mark solid class="h-4 w-4 inline-block" />
            <span class="inline-block align-middle">Failed</span>
          </div>
        </Common.button>
      <% :success -> %>
        <Common.button color="green" id="test-button">
          <div class="h-full -ml-1">
            <Heroicons.check solid class="h-4 w-4 inline-block" />
            <span class="inline-block align-middle">Success</span>
          </div>
        </Common.button>
      <% :unknown -> %>
        <Common.button_white phx-click="test" phx-target={@myself} id="test-button">
          <div class="h-full -ml-1">
            <Heroicons.beaker solid class="h-4 w-4 inline-block" />
            <span class="inline-block align-middle">Test</span>
          </div>
        </Common.button_white>
      <% _ -> %>
    <% end %>
    """
  end
end
