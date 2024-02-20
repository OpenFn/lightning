defmodule LightningWeb.CredentialLive.Scopes do
  @moduledoc false
  use LightningWeb, :component

  attr :id, :string, required: true
  attr :on_change, :any, required: true
  attr :target, :any, required: true
  attr :authorize_url, :string, required: true
  attr :credential_type, :string, required: true
  attr :selected_scopes, :any, required: true

  def scopes_picklist(assigns) do
    {enabled_scopes, disabled_scopes} =
      assigns.credential_type |> credential_type_to_provider |> get_scopes

    assigns =
      assigns
      |> Map.put_new(:scopes, (disabled_scopes ++ enabled_scopes) |> Enum.sort())
      |> Map.put_new(:disabled_scopes, disabled_scopes)

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
          Learn more about <%= provider(@credential_type) %> permissions
          <a
            target="_blank"
            href={oauth2_scopes_help_url(@credential_type)}
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
                checked={Enum.member?(@disabled_scopes ++ @selected_scopes, scope)}
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

  defp credential_type_to_provider(credential_type) do
    case credential_type do
      "googlesheets" -> "google"
      "salesforce_oauth" -> "salesforce"
    end
  end

  def get_scopes(provider) do
    case provider do
      "google" ->
        {[], ~W(userinfo.email userinfo.profile spreadsheets)}

      "salesforce" ->
        {~w(cdp_query_api pardot_api cdp_profile_api chatter_api cdp_ingest_api
      eclair_api wave_api api custom_permissions id lightning content openid full visualforce
      web chatbot_api user_registration_api forgot_password cdp_api sfap_api interaction_api),
         ~w(refresh_token)}
    end
  end

  defp provider(credential_type) do
    case credential_type do
      "googlesheets" -> "Google"
      "salesforce_oauth" -> "Salesforce"
    end
  end

  defp oauth2_scopes_help_url(credential_type) do
    case credential_type do
      "googlesheets" ->
        "https://developers.google.com/identity/protocols/oauth2/scopes"

      "salesforce_oauth" ->
        "https://help.salesforce.com/s/articleView?id=sf.remoteaccess_oauth_tokens_scopes.htm&type=5"
    end
  end
end
