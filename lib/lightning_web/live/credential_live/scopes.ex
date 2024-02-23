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

    %{optional: optional_scopes, mandatory: mandatory_scopes} = adapter.scopes()

    scopes = mandatory_scopes ++ optional_scopes
    checked_scopes = mandatory_scopes ++ assigns.selected_scopes

    assigns =
      assigns
      |> Map.put_new(:scopes, Enum.sort(scopes))
      |> Map.put_new(:mandatory_scopes, mandatory_scopes)
      |> Map.put_new(:checked_scopes, checked_scopes)
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
          <.input
            id={"#{@id}_#{scope}"}
            type="checkbox"
            name={scope}
            value={scope}
            checked={scope in @checked_scopes}
            disabled={scope in @mandatory_scopes}
            phx-change={@on_change}
            phx-target={@target}
            label={scope}
          />
        <% end %>
      </div>
    </div>
    """
  end
end
