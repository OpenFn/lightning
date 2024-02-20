defmodule LightningWeb.CredentialLive.Salesforce do
  @moduledoc false
  use LightningWeb, :component

  @salesforce_scopes ~w(cdp_query_api pardot_api cdp_profile_api chatter_api cdp_ingest_api
  eclair_api wave_api api custom_permissions id lightning content openid full visualforce
  web chatbot_api user_registration_api forgot_password cdp_api sfap_api interaction_api)

  @predefined_salesforce_scopes ~w(refresh_token)
  # @predefined_google_scopes ~W(spreadsheets userinfo.profile)

  attr :id, :string, required: true
  attr :on_change, :any, required: true
  attr :target, :any, required: true
  attr :authorize_url, :string, required: true
  attr :selected_scopes, :any, required: true

  def scopes(assigns) do
    assigns =
      assigns
      |> Map.put_new(
        :scopes,
        @predefined_salesforce_scopes ++ @salesforce_scopes
      )
      |> Map.put_new(:disabled_scopes, @predefined_salesforce_scopes)

    ~H"""
    <div id={@id}>
      <h3 class="leading-6 text-slate-800 pb-2">
        <div class="flex flex-row text-sm font-semibold ">
          Select permissions
          <LightningWeb.Components.Common.tooltip
            id={"#{@id}-tooltip"}
            title="Select permissions associated to your OAuth2 Token"
          />
        </div>
        <div class="flex flex-row text-xs">
          Learn more about Salesforce permissions
          <a
            target="_blank"
            href="https://help.salesforce.com/s/articleView?id=sf.remoteaccess_oauth_tokens_scopes.htm&type=5"
            class="whitespace-nowrap font-medium text-blue-700 hover:text-blue-600"
          >
            &nbsp;here
          </a>
        </div>
      </h3>
      <div class="grid grid-cols-4 gap-1">
        <%= for scope <- @scopes do %>
          <div class="form-check">
            <label class="form-check-label inline-block">
              <input
                id={"#{@id}_#{scope}"}
                type="checkbox"
                name={scope}
                checked={
                  Enum.member?(@selected_scopes, scope) or
                    Enum.member?(@disabled_scopes, scope)
                }
                disabled={Enum.member?(@disabled_scopes, scope)}
                phx-change={@on_change}
                phx-target={@target}
                class="form-check-input appearance-none h-4 w-4 border border-gray-300 rounded-sm bg-white checked:disabled:bg-blue-300 checked:disabled:border-blue-300 checked:bg-blue-600 checked:border-blue-600 focus:outline-none transition duration-200 mt-1 align-top bg-no-repeat bg-center bg-contain float-left cursor-pointer"
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
