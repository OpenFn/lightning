defmodule LightningWeb.LayoutComponentsTest do
  @moduledoc false
  use LightningWeb.ConnCase

  import Phoenix.LiveViewTest

  alias LightningWeb.LayoutComponents

  test "menu_item/1 renders active menu item" do
    icon = &Heroicons.academic_cap/1

    Application.put_env(:lightning, :menu_items,
      some_assign_present: [
        {"/somepath", icon, "CustomMenuName", :the_active_menu}
      ]
    )

    on_exit(fn -> Application.delete_env(:lightning, :menu_items) end)

    assigns = %{
      some_assign_present: :any,
      active_menu_item: :the_active_menu
    }

    html = render_component(&LayoutComponents.menu_items/1, assigns)

    assert html =~ render_component(icon, %{class: "h-5 w-5 inline-block mr-1"})
    assert html =~ "CustomMenuName"
  end
end
