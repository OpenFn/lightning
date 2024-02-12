defmodule LightningWeb.CoreComponents do
  @moduledoc false

  use Phoenix.Component

  # TODO: Remove `Phoenix.HTML` and `error_tag` once we are in
  # a better position to conform the more recent Phoenix conventions.
  # use Phoenix.HTML

  import LightningWeb.Components.NewInputs

  alias Phoenix.LiveView.JS

  @doc ~S"""
  Renders a table with generic styling.

  ## Examples

      <.new_table id="users" rows={@users}>
        <:col :let={user} label="id"><%= user.id %></:col>
        <:col :let={user} label="username"><%= user.username %></:col>
      </.new_table>
  """

  attr :id, :string, required: true
  attr :row_click, :any, default: nil
  attr :rows, :list, required: true
  attr :row_class, :string, default: ""

  slot :col, required: true do
    attr :label, :string
    attr :label_class, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def new_table(assigns) do
    ~H"""
    <div
      id={@id}
      class="overflow-hidden shadow ring-1 ring-black ring-opacity-5 sm:rounded-lg"
    >
      <table class="min-w-full divide-y divide-gray-300">
        <thead class="">
          <tr>
            <th
              :for={col <- @col}
              scope="col"
              class="px-3 py-3.5 text-left text-sm font-semibold text-gray-500"
            >
              <div class={col[:label_class]}>
                <%= col[:label] %>
              </div>
            </th>
            <th
              :if={@action != []}
              scope="col"
              class="relative py-3.5 pl-3 pr-4 sm:pr-6"
            >
              <span class="sr-only">Actions</span>
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-gray-200 bg-white">
          <tr
            :for={row <- @rows}
            id={"#{@id}-#{Phoenix.Param.to_param(row)}"}
            class={[@row_class]}
          >
            <td
              :for={col <- @col}
              phx-click={@row_click && @row_click.(row)}
              class={[
                "whitespace-nowrap px-3 py-4 text-sm text-gray-500",
                @row_click && "hover:cursor-pointer"
              ]}
            >
              <%= render_slot(col, row) %>
            </td>
            <td :if={@action != []} class="p-0 w-14">
              <div class="relative whitespace-nowrap py-4 text-right text-sm font-medium">
                <span
                  :for={action <- @action}
                  class="relative ml-4 font-semibold leading-6 text-zinc-900 hover:text-zinc-700"
                >
                  <%= render_slot(action, row) %>
                </span>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Generates tag for inlined form input errors.
  """

  attr :field, Phoenix.HTML.FormField,
    doc:
      "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :any, required: false

  def old_error(%{field: field} = assigns) do
    assigns =
      assigns |> assign(:errors, Enum.map(field.errors, &translate_error(&1)))

    ~H"""
    <.error :for={msg <- @errors}><%= msg %></.error>
    """
  end

  def old_error(%{errors: errors} = assigns) do
    assigns =
      assigns |> assign(:errors, Enum.map(errors, &translate_error(&1)))

    ~H"""
    <.error :for={msg <- @errors}><%= msg %></.error>
    """
  end

  def show_dropdown(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.show(
      to: "##{id}",
      transition:
        {"transition ease-out duration-100", "transform opacity-0 scale-95",
         "transform opacity-100 scale-100"}
    )
  end

  def hide_dropdown(js \\ %JS{}, id) do
    js
    |> JS.hide(
      to: "##{id}",
      transition:
        {"transition ease-in duration-75", "transform opacity-100 scale-100",
         "transform opacity-0 scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(LightningWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(LightningWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end

  @doc """
  Translates the errors for a given Ecto Changeset
  """
  def translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      translate_error({msg, opts})
    end)
  end
end
