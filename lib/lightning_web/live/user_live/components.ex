defmodule LightningWeb.UserLive.Components do
  use LightningWeb, :component

  import PetalComponents.Table

  attr :socket, :map, required: true
  attr :users, :list, required: true
  attr :live_action, :atom, required: true

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
    <.table>
      <.tr>
        <.th>First name</.th>
        <.th>Last name</.th>
        <.th>Email</.th>
        <.th>Role*</.th>
        <.th>Enabled?</.th>
        <.th>Support?</.th>
        <.th>Scheduled Deletion</.th>
        <.th>Actions</.th>
      </.tr>
      <%= for user <- @users do %>
        <.tr id={"user-#{user.id}"}>
          <.td>{user.first_name}</.td>
          <.td>{user.last_name}</.td>
          <.td>{user.email}</.td>
          <.td>{user.role}</.td>
          <.td>
            <%= if !user.disabled do %>
              <Heroicons.check_circle solid class="w-6 h-6 text-gray-500" />
            <% end %>
          </.td>
          <.td>
            <%= if user.support_user do %>
              <div class="content-center">
                <Heroicons.check_circle solid class="w-6 h-6 text-gray-500" />
              </div>
            <% end %>
          </.td>
          <.td>{user.scheduled_deletion}</.td>
          <.td class="py-0.5">
            <span>
              <.link
                class="table-action"
                navigate={Routes.user_edit_path(@socket, :edit, user)}
              >
                Edit
              </.link>
            </span>
            <.delete_action
              user={user}
              delete_url={Routes.user_index_path(@socket, :delete, user)}
            />
          </.td>
        </.tr>
      <% end %>
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
      <.cancel_deletion user={@user} /> |
      <span id={"delete-now-#{@user.id}"} class="table-action-disabled">
        Delete now
      </span>
      """
    else
      ~H"""
      <span id={"delete-#{@user.id}"} class="table-action-disabled">
        Delete
      </span>
      """
    end
  end

  defp delete_action(%{user: %{role: :user}} = assigns) do
    if assigns.user.scheduled_deletion do
      ~H"""
      <.cancel_deletion user={@user} /> |
      <span>
        <.link
          id={"delete-now-#{@user.id}"}
          class="table-action"
          navigate={@delete_url}
        >
          Delete now
        </.link>
      </span>
      """
    else
      ~H"""
      <span>
        <.link id={"delete-#{@user.id}"} class="table-action" navigate={@delete_url}>
          Delete
        </.link>
      </span>
      """
    end
  end

  defp cancel_deletion(assigns) do
    ~H"""
    <span>
      <.link
        id={"cancel-deletion-#{@user.id}"}
        href="#"
        phx-click="cancel_deletion"
        phx-value-id={@user.id}
        class="table-action"
      >
        Cancel deletion
      </.link>
    </span>
    """
  end
end
