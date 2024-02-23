defmodule LightningWeb.CredentialLiveHelpers do
  import Phoenix.LiveViewTest
  import ExUnit.Assertions

  def delete_credential_button(live, id) do
    live
    |> element("[phx-click='delete_project'][phx-value-projectid='#{id}']")
  end

  def select_credential_type(live, type) do
    html =
      live
      |> form("#credential-schema-picker", selected: type)
      |> render_change()

    assert Floki.parse_fragment!(html)
           |> Floki.find("input[type=radio][value=#{type}]")
           |> Enum.any?(),
           "Expected #{type} to be selected"
  end

  def click_continue(live) do
    live
    |> element("button", "Configure credential")
    |> render_click()
  end

  def fill_credential(live, params, form_id \\ "#credential-form-new")
      when is_map(params) do
    live
    |> form(form_id, credential: params)
    |> render_change()
  end

  def click_save(live, form_data \\ %{}, form_id \\ "#credential-form-new") do
    live
    |> form(form_id, form_data)
    |> render_submit()
  end
end
