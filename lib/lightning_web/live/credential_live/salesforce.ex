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
  attr :dirty, :boolean, required: true
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
      <h3 class="text-sm font-semibold leading-6 text-slate-800 pb-2">
        <div class="flex flex-row">
          Scopes
          <LightningWeb.Components.Common.tooltip
            id={"#{@id}-tooltip"}
            title="Select permissions associated to your OAuth2 Token"
          />
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
      <div class={"#{if !@dirty, do: "opacity-0", else: "opacity-100"} transition-opacity ease-in duration-700 rounded-md bg-blue-50 border border-blue-100 p-1 my-4"}>
        <div class="flex">
          <div class="flex-shrink-0">
            <svg
              class="h-5 w-5 text-blue-400"
              viewBox="0 0 20 20"
              fill="currentColor"
              aria-hidden="true"
            >
              <path
                fill-rule="evenodd"
                d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a.75.75 0 000 1.5h.253a.25.25 0 01.244.304l-.459 2.066A1.75 1.75 0 0010.747 15H11a.75.75 0 000-1.5h-.253a.25.25 0 01-.244-.304l.459-2.066A1.75 1.75 0 009.253 9H9z"
                clip-rule="evenodd"
              />
            </svg>
          </div>
          <div class="ml-3 flex-1 md:flex md:justify-between">
            <p class="text-sm text-slate-700">
              Please re-authenticate to save your credential with the updated scopes
            </p>
            <p class="mt-3 text-sm md:ml-6 md:mt-0">
              <a
                target="_blank"
                href={@authorize_url}
                class="whitespace-nowrap font-medium text-blue-700 hover:text-blue-600"
              >
                Re-authenticate <span aria-hidden="true"> &rarr;</span>
              </a>
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
