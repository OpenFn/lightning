defmodule LightningWeb.CredentialLiveHelpers do
  import Phoenix.LiveViewTest
  import ExUnit.Assertions

  def open_create_credential_modal(view) do
    view
    |> element("#new-credential-option-menu-item")
    |> render_click()
  end

  def open_edit_credential_modal(view, credential_id) do
    view
    |> element("#credential-actions-#{credential_id}-edit")
    |> render_click()
  end

  def open_delete_credential_modal(view, credential_id) do
    view
    |> element("#credential-actions-#{credential_id}-delete")
    |> render_click()
  end

  def open_transfer_credential_modal(view, credential_id) do
    view
    |> element("#credential-actions-#{credential_id}-transfer")
    |> render_click()
  end

  def delete_credential_button(live, id) do
    live
    |> element(
      "[phx-click='remove_selected_project'][phx-value-project_id='#{id}']"
    )
  end

  def select_credential_type(live, type) do
    html =
      live
      |> form("#credential-schema-picker", selected: type)
      |> render_change()

    assert html
           |> Floki.parse_fragment!()
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
