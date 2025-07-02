defmodule LightningWeb.UserLive.Components do
  use LightningWeb, :component

  attr :socket, :map, required: true
  attr :users, :list, required: true
  attr :live_action, :atom, required: true
  attr :sort_key, :string, default: "email"
  attr :sort_direction, :string, default: "asc"
  attr :target, :any, default: nil
  attr :filter, :string, default: ""

  attr :user_deletion_modal, :atom,
    default: LightningWeb.Components.UserDeletionModal

  attr :delete_user, Lightning.Accounts.User, default: nil

  def users_table(assigns) do
    ~H"""
    <.live_component
      :if={@live_action == :delete}
      module={@user_deletion_modal}
      id={"user-details-#{@delete_user.id}"}
      user={@delete_user}
      is_current_user={false}
      logout={false}
      return_to={Routes.user_index_path(@socket, :index)}
    />

    <LightningWeb.Live.Helpers.TableHelpers.filter_input
      filter={@filter}
      placeholder="Filter users..."
      target={@target}
    />

    <.table>
      <:header>
        <.tr>
          <.th
            sortable={true}
            sort_by="first_name"
            active={@sort_key == "first_name"}
            sort_direction={@sort_direction}
            {if @target, do: [phx_target: @target], else: []}
          >
            First name
          </.th>
          <.th
            sortable={true}
            sort_by="last_name"
            active={@sort_key == "last_name"}
            sort_direction={@sort_direction}
            {if @target, do: [phx_target: @target], else: []}
          >
            Last name
          </.th>
          <.th
            sortable={true}
            sort_by="email"
            active={@sort_key == "email"}
            sort_direction={@sort_direction}
            {if @target, do: [phx_target: @target], else: []}
          >
            Email
          </.th>
          <.th
            sortable={true}
            sort_by="role"
            active={@sort_key == "role"}
            sort_direction={@sort_direction}
            {if @target, do: [phx_target: @target], else: []}
          >
            Role*
          </.th>
          <.th
            sortable={true}
            sort_by="enabled"
            active={@sort_key == "enabled"}
            sort_direction={@sort_direction}
            {if @target, do: [phx_target: @target], else: []}
          >
            Enabled?
          </.th>
          <.th
            sortable={true}
            sort_by="support_user"
            active={@sort_key == "support_user"}
            sort_direction={@sort_direction}
            {if @target, do: [phx_target: @target], else: []}
          >
            Support?
          </.th>
          <.th
            sortable={true}
            sort_by="scheduled_deletion"
            active={@sort_key == "scheduled_deletion"}
            sort_direction={@sort_direction}
            {if @target, do: [phx_target: @target], else: []}
          >
            Scheduled Deletion
          </.th>
          <.th>Actions</.th>
        </.tr>
      </:header>
      <:body>
        <%= for user <- @users do %>
          <.tr id={"user-#{user.id}"}>
            <.td
              class="overflow-hidden text-ellipsis max-w-40"
              title={user.first_name}
            >
              {user.first_name}
            </.td>
            <.td
              class="overflow-hidden text-ellipsis max-w-40"
              title={user.last_name}
            >
              {user.last_name}
            </.td>
            <.td class="max-w-48 overflow-hidden text-ellipsis" title={user.email}>
              {user.email}
            </.td>
            <.td>{user.role}</.td>
            <.td>
              <.icon
                :if={!user.disabled}
                name="hero-check-circle-solid"
                class="w-6 h-6 text-gray-500"
              />
            </.td>
            <.td>
              <.icon
                :if={user.support_user}
                name="hero-check-circle-solid"
                class="w-6 h-6 text-gray-500"
              />
            </.td>
            <.td>
              {user.scheduled_deletion &&
                Calendar.strftime(user.scheduled_deletion, "%d %b  %H:%M")}
            </.td>
            <.td class="py-0.5">
              <Common.simple_dropdown
                id={"user-actions-#{user.id}-dropdown"}
                button_theme="secondary"
              >
                <:button>
                  Actions
                </:button>

                <:options>
                  <.link navigate={Routes.user_edit_path(@socket, :edit, user)}>
                    Edit
                  </.link>
                  <.delete_action
                    user={user}
                    delete_url={Routes.user_index_path(@socket, :delete, user)}
                  />
                </:options>
              </Common.simple_dropdown>
            </.td>
          </.tr>
        <% end %>
      </:body>
    </.table>
    <br />
    <.p>
      *Note that a <code>superuser</code> can access <em>everything</em> in a
      Lightning installation across all projects, including this page. Most
      day-to-day user management (adding and removing collaborators) will be
      done by project "admins" via the project settings page.
    </.p>
    """
  end

  attr :delete_url, :string, required: true
  attr :user, :string, required: true

  defp delete_action(%{user: %{role: :superuser}} = assigns) do
    if assigns.user.scheduled_deletion do
      ~H"""
      <.cancel_deletion user={@user} />
      <span id={"delete-now-#{@user.id}"} class="cursor-not-allowed">
        Delete now
      </span>
      """
    else
      ~H"""
      <span id={"delete-#{@user.id}"} class="cursor-not-allowed">
        Delete
      </span>
      """
    end
  end

  defp delete_action(%{user: %{role: :user}} = assigns) do
    if assigns.user.scheduled_deletion do
      ~H"""
      <.cancel_deletion user={@user} />
      <.link id={"delete-now-#{@user.id}"} navigate={@delete_url}>
        Delete now
      </.link>
      """
    else
      ~H"""
      <.link id={"delete-#{@user.id}"} navigate={@delete_url}>
        Delete
      </.link>
      """
    end
  end

  defp cancel_deletion(assigns) do
    ~H"""
    <.link
      id={"cancel-deletion-#{@user.id}"}
      href="#"
      phx-click="cancel_deletion"
      phx-value-id={@user.id}
    >
      Cancel deletion
    </.link>
    """
  end
end
