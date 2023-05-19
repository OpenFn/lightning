defmodule LightningWeb.CoreComponents do
  @moduledoc false

  use Phoenix.Component

  # TODO: Remove `Phoenix.HTML` and `error_tag` once we are in
  # a better position to conform the more recent Phoenix conventions.
  use Phoenix.HTML

  @doc """
  Generates tag for inlined form input errors.
  """
  def error_tag(form, field), do: error_tag(form, field, [])

  def error_tag(form, field, attrs) when is_list(attrs) do
    Enum.map(Keyword.get_values(form.errors, field), fn error ->
      content_tag(
        :span,
        translate_error(error),
        Keyword.merge(
          [phx_feedback_for: Phoenix.HTML.Form.input_name(form, field)],
          attrs
        )
      )
    end)
  end

  def translate_error({msg, opts}) do
    # You can make use of gettext to translate error messages by
    # uncommenting and adjusting the following code:

    # if count = opts[:count] do
    #   Gettext.dngettext(LightningWeb.Gettext, "errors", msg, msg, count, opts)
    # else
    #   Gettext.dgettext(LightningWeb.Gettext, "errors", msg, opts)
    # end

    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
