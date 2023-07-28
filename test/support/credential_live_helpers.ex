defmodule LightningWeb.CredentialLiveHelpers do
  import Phoenix.LiveViewTest

  def select_credential_type(live, type) do
    live
    |> form("#credential-type-picker", type: %{selected: type})
    |> render_change()
  end

  def click_continue(live) do
    live
    |> element("button", "Continue")
    |> render_click()
  end

  def fill_credential(live, params) when is_map(params) do
    live
    |> form("#credential-form", credential: params)
    |> render_change()
  end

  def click_save(live, form_data \\ %{}) do
    live
    |> form("#credential-form", form_data)
    |> render_submit()
  end
end
