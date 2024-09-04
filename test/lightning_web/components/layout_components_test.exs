defmodule LightningWeb.LayoutComponentsTest do
  @moduledoc false
  use LightningWeb.ConnCase

  import Phoenix.LiveViewTest

  alias LightningWeb.LayoutComponents
  alias LightningWeb.Components.Menu

  test "menu_item/1 renders custom menu items" do
    on_exit(fn -> Application.delete_env(:lightning, :menu_items) end)

    Application.put_env(:lightning, :menu_items, %{
      component: &Menu.project_items/1,
      assigns_keys: [:project_id, :active_menu_item]
    })

    project_id = Ecto.UUID.generate()

    assigns = %{
      active_menu_item: :settings,
      project_id: project_id
    }

    element =
      (&LayoutComponents.menu_items/1)
      |> render_component(assigns)
      |> Floki.find("a[href='/projects/#{project_id}/settings']")

    assert Floki.text(element) == "Settings"

    assert element |> Floki.attribute("class") |> hd =~
             "menu-item-active"
  end
end
