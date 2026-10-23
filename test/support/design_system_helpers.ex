defmodule LightningWeb.DesignSystemHelpers do
  @moduledoc """
  Drives a design-system page the way its React island does: reads its
  `data-props` and pushes its events to the LiveView.
  """
  import ExUnit.Assertions
  import Phoenix.LiveViewTest

  # Written from each page's `Props` type by `npm run ds:schemas` in assets/.
  @schemas Path.expand("design_system_schemas", __DIR__)

  @doc """
  The decoded `data-props` of the page mounted at `selector`. Fails unless
  they match the page's `Props` type, field by field.
  """
  def page_props(view, selector) do
    html = view |> element(selector) |> render() |> Floki.parse_fragment!()
    # A page by its island; the shell's sidebar, which has none, by its hook.
    [name | _] =
      Floki.attribute(html, "data-react-name") ++
        Floki.attribute(html, "phx-hook")

    props =
      html |> Floki.attribute("data-props") |> List.first() |> Jason.decode!()

    assert_props_match!(name, props)
    props
  end

  defp assert_props_match!(name, props) do
    path = Path.join(@schemas, "#{name}.json")

    unless File.exists?(path),
      do: flunk("No schema for #{name}. Run `npm run ds:schemas` in assets/.")

    schema =
      path |> File.read!() |> Jason.decode!() |> ExJsonSchema.Schema.resolve()

    case ExJsonSchema.Validator.validate(schema, props) do
      :ok ->
        :ok

      {:error, errors} ->
        flunk("""
        #{name}'s data-props don't match its Props type \
        (assets/js/design-system):
        #{Enum.map_join(errors, "\n", fn {message, at} -> "  #{at}: #{message}" end)}
        """)
    end
  end

  @doc "Sends an event from the page, as the kit's `send` and `request` do."
  def push_page_event(view, selector, event, payload \\ %{}) do
    view |> element(selector) |> render_hook(event, payload)
  end
end
