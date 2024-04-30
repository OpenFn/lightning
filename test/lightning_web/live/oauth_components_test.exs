defmodule LightningWeb.OauthComponentsTest do
  use LightningWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "scopes_picklist/1" do
    selected_scopes = ~w(scope_1 scope_2 scope_3 scope_4)
    mandatory_scopes = ~w(scope_1 scope_2)
    scopes = ~w(scope_1 scope_2 scope_3 scope_4 scope_5 scope_6)

    picklist =
      render_component(&LightningWeb.Components.Oauth.scopes_picklist/1,
        id: "scopes_picklist",
        on_change: "scopes_changed",
        target: nil,
        selected_scopes: selected_scopes,
        mandatory_scopes: mandatory_scopes,
        scopes: scopes,
        provider: "DHIS2",
        doc_url: "https://dhis2.org/oauth/scopes"
      )

    assert picklist =~ "Select permissions associated to your OAuth2 Token"

    scopes_dom = Floki.parse_document!(picklist)

    checked_checkboxes =
      Floki.find(scopes_dom, "input[type='checkbox'][checked]")

    assert length(checked_checkboxes) === length(selected_scopes)

    checked_scope_names =
      Enum.map(checked_checkboxes, fn {"input", attrs, _children} ->
        attrs |> Enum.find(fn {key, _value} -> key == "name" end) |> elem(1)
      end)

    checked_scope_names_sorted = Enum.sort(checked_scope_names)
    selected_scopes_sorted = Enum.sort(selected_scopes)

    assert checked_scope_names_sorted == selected_scopes_sorted
  end

  test "rendering error component for various error type" do
    render_component(
      &LightningWeb.Components.Oauth.error_block/1,
      type: :token_failed,
      authorize_url: "https://www",
      myself: nil,
      provider: "Salesforce"
    ) =~ "Failed retrieving the token from the provider"

    render_component(
      &LightningWeb.Components.Oauth.error_block/1,
      type: :refresh_failed,
      authorize_url: "https://www",
      myself: nil,
      provider: "Salesforce"
    ) =~ "Failed renewing your access token"

    render_component(
      &LightningWeb.Components.Oauth.error_block/1,
      type: :userinfo_failed,
      authorize_url: "https://www",
      myself: nil,
      provider: "Salesforce"
    ) =~ "Failed retrieving your information"

    render_component(&LightningWeb.Components.Oauth.error_block/1,
      type: :code_failed,
      authorize_url: "https://www",
      myself: nil,
      provider: "Salesforce"
    ) =~ "Failed retrieving authentication code."

    render_component(
      &LightningWeb.Components.Oauth.error_block/1,
      type: :no_refresh_token,
      authorize_url: "https://www",
      myself: nil,
      provider: "Salesforce"
    ) =~ "The token is missing it's"
  end
end
