defmodule LightningWeb.CredentialLive.Salesforce do
  @moduledoc false
  use LightningWeb, :component

  @scopes ~W(cdp_query_api pardot_api cdp_profile_api chatter_api cdp_ingest_api
eclair_api wave_api api custom_permissions id profile email address phone lightning
content openid full visualforce web chatbot_api user_registration_api forgot_password
cdp_api sfap_api interaction_api)

  attr :id, :string, required: true
  attr :on_change, :any, required: true
  attr :target, :any, required: true
  attr :selected_scopes, :any, required: true

  def scopes(assigns) do
    assigns = Map.put_new(assigns, :scopes, @scopes)

    ~H"""
    <div id={@id}>
      <h3 class="text-base font-semibold leading-6 text-gray-900 pb-2">
        Pick the scopes to authorize
      </h3>
      <div class="grid grid-cols-4 gap-1">
        <%= for scope <- @scopes do %>
          <div class="form-check">
            <label class="form-check-label inline-block">
              <input
                id={"scope_#{scope}"}
                type="checkbox"
                name={scope}
                checked={Enum.member?(@selected_scopes, scope)}
                phx-change={@on_change}
                phx-target={@target}
                class="form-check-input appearance-none h-4 w-4 border border-gray-300 rounded-sm bg-white checked:bg-blue-600 checked:border-blue-600 focus:outline-none transition duration-200 mt-1 align-top bg-no-repeat bg-center bg-contain float-left cursor-pointer"
              />
              <span class="ml-2"><%= scope %></span>
            </label>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
