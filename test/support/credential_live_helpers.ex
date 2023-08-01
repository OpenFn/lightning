defmodule LightningWeb.CredentialLiveHelpers do
  import Phoenix.LiveViewTest
  import ExUnit.Assertions

  def select_credential_type(live, type) do
    html =
      live
      |> form("#credential-type-picker", type: %{selected: type})
      |> render_change()

    assert Floki.parse_fragment!(html)
           |> Floki.find("input[type=radio][value=#{type}][checked]")
           |> Enum.any?(),
           "Expected #{type} to be selected"
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
