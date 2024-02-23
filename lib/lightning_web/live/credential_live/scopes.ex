defmodule LightningWeb.CredentialLive.Scopes do
  @moduledoc false
  use LightningWeb, :component

  alias Lightning.Credentials

  attr :id, :string, required: true
  attr :on_change, :any, required: true
  attr :target, :any, required: true
  attr :schema, :string, required: true
  attr :selected_scopes, :any, required: true

  def scopes_picklist(assigns) do
    adapter = Credentials.lookup_adapter(assigns.schema)

    %{enabled: enabled_scopes, disabled: disabled_scopes} = adapter.scopes()

    scopes = disabled_scopes ++ enabled_scopes

    assigns =
      assigns
      |> Map.put_new(:scopes, Enum.sort(scopes))
      |> Map.put_new(:disabled_scopes, disabled_scopes)
      |> Map.put_new(:provider, adapter.provider_name())
      |> Map.put_new(:doc_url, adapter.scopes_doc_url())

    ~H"""
    <div id={@id}>
      <h3 class="leading-6 text-slate-800 pb-2 mb-2">
        <div class="flex flex-row text-sm font-semibold">
          Select permissions
          <LightningWeb.Components.Common.tooltip
            id={"#{@id}-tooltip"}
            title="Select permissions associated to your OAuth2 Token"
          />
        </div>
        <div class="flex flex-row text-xs mt-1">
          Learn more about <%= @provider %> permissions
          <a
            target="_blank"
            href={@doc_url}
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
end
