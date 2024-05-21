defmodule LightningWeb.Components.Menu do
  use LightningWeb, :component

  def project_items(assigns) do
    ~H"""
    <Settings.menu_item
      to={~p"/projects/#{@project_id}/w"}
      active={@active_menu_item == :overview}
    >
      <Icon.workflows class="h-5 w-5 inline-block mr-2 align-middle" />
      <span class="inline-block align-middle">Workflows</span>
    </Settings.menu_item>

    <Settings.menu_item
      to={~p"/projects/#{@project_id}/history"}
      active={@active_menu_item == :runs}
    >
      <Icon.runs class="h-5 w-5 inline-block mr-2" />
      <span class="inline-block align-middle">History</span>
    </Settings.menu_item>

    <Settings.menu_item
      to={"/projects/#{@project_id}/settings"}
      active={@active_menu_item == :settings}
    >
      <Icon.settings class="h-5 w-5 inline-block mr-2" />
      <span class="inline-block align-middle">Settings</span>
    </Settings.menu_item>
    <!-- # Commented out until new dataclips/globals list is fully functional. -->
    <!--
      <Settings.menu_item
        to={Routes.project_dataclip_index_path(@socket, :index, @project.id)}
        active={@active_menu_item == :dataclips}>
        <Icon.dataclips class="h-5 w-5 inline-block mr-2" />
        <span class="inline-block align-middle">Dataclips</span>
      </Settings.menu_item>
    -->
    """
  end

  def profile_items(assigns) do
    ~H"""
    <Settings.menu_item to={~p"/profile"} active={@active_menu_item == :profile}>
      <Heroicons.user_circle class="h-5 w-5 inline-block mr-2" /> User Profile
    </Settings.menu_item>
    <Settings.menu_item
      to={~p"/credentials"}
      active={@active_menu_item == :credentials}
    >
      <Heroicons.key class="h-5 w-5 inline-block mr-2" /> Credentials
    </Settings.menu_item>
    <Settings.menu_item
      to={~p"/profile/tokens"}
      active={@active_menu_item == :tokens}
    >
      <Heroicons.command_line class="h-5 w-5 inline-block mr-2" /> API Tokens
    </Settings.menu_item>
    """
  end
end
