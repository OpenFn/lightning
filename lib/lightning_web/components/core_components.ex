defmodule LightningWeb.CoreComponents do
  @moduledoc false

  use Phoenix.Component

  # TODO: Remove `Phoenix.HTML` and `error_tag` once we are in
  # a better position to conform the more recent Phoenix conventions.
  # use Phoenix.HTML

  import LightningWeb.Components.NewInputs

  alias Phoenix.LiveView.JS

  def plausible_script(assigns) do
    config = Application.get_env(:lightning, :plausible, [])

    assigns =
      if config[:src] do
        assigns
        |> assign(
          enabled: true,
          src: config[:src],
          data_domain: config[:data_domain]
        )
      else
        assigns |> assign(enabled: false)
      end

    ~H"""
    <script :if={@enabled} defer src={@src} data-domain={@data_domain}>
    </script>
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
