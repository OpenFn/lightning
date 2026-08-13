defmodule LightningWeb.Components.NewInputsTest do
  @moduledoc false
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias LightningWeb.Components.NewInputs
  alias LightningWeb.CoreComponents

  # A minimal embedded schema used to produce real Ecto changesets whose
  # `used_input?` behaviour varies depending on whether the params map
  # contains the field key.
  defmodule Item do
    use Ecto.Schema

    embedded_schema do
      field :name, :string
    end

    def changeset(item \\ %__MODULE__{}, params) do
      Ecto.Changeset.cast(item, params, [:name])
      |> Ecto.Changeset.validate_required([:name])
    end
  end

  # --- helpers ---------------------------------------------------------------

  # Build a form where `:name` has NOT been touched by the user (no "name"
  # key in the params map), yet the changeset carries a validation error
  # because `validate_required` fails.
  defp unused_field_form do
    Item.changeset(%{})
    |> Map.put(:action, :validate)
    |> Phoenix.Component.to_form()
  end

  # Build a form where `:name` HAS been touched (the params map contains
  # `"name" => ""`), so `used_input?` returns true, and the required
  # validation still fails.
  defp used_field_form do
    Item.changeset(%{"name" => ""})
    |> Map.put(:action, :validate)
    |> Phoenix.Component.to_form()
  end

  # ---- input/1 --------------------------------------------------------------

  describe "input/1 used_input? gating" do
    test "unused field does not render error messages" do
      form = unused_field_form()

      html =
        render_component(&NewInputs.input/1, %{
          field: form[:name],
          type: "text"
        })

      refute html =~ "data-tag=\"error_message\""
      refute html =~ "can&#39;t be blank"
    end

    test "used field renders error messages" do
      form = used_field_form()

      html =
        render_component(&NewInputs.input/1, %{
          field: form[:name],
          type: "text"
        })

      assert html =~ "data-tag=\"error_message\""
      assert html =~ "can&#39;t be blank"
    end

    test "display_errors=false suppresses errors even on used fields" do
      form = used_field_form()

      html =
        render_component(&NewInputs.input/1, %{
          field: form[:name],
          type: "text",
          display_errors: false
        })

      refute html =~ "data-tag=\"error_message\""
      refute html =~ "can&#39;t be blank"
    end
  end

  # ---- errors/1 -------------------------------------------------------------

  describe "errors/1 used_input? gating" do
    test "unused field does not render error messages" do
      form = unused_field_form()

      html =
        render_component(&NewInputs.errors/1, %{field: form[:name]})

      refute html =~ "data-tag=\"error_message\""
      refute html =~ "can&#39;t be blank"
    end

    test "used field renders error messages" do
      form = used_field_form()

      html =
        render_component(&NewInputs.errors/1, %{field: form[:name]})

      assert html =~ "data-tag=\"error_message\""
      assert html =~ "can&#39;t be blank"
    end
  end

  # ---- autocomplete defaults --------------------------------------------------

  describe "autocomplete defaults" do
    test "input/1 renders autocomplete='off' by default" do
      form = used_field_form()

      html =
        render_component(&NewInputs.input/1, %{
          field: form[:name],
          type: "text"
        })

      assert html =~ ~s(autocomplete="off")
    end

    test "input/1 allows explicit autocomplete override" do
      form = used_field_form()

      html =
        render_component(&NewInputs.input/1, %{
          field: form[:name],
          type: "text",
          autocomplete: "email"
        })

      assert html =~ ~s(autocomplete="email")
    end
  end

  # Renders a `local-datetime` filter field the way the history page does, from
  # the params that page keeps in the URL.
  defp render_local_datetime(params) do
    types = %{date_after: :utc_datetime}

    form =
      {%{}, types}
      |> Ecto.Changeset.cast(params, [:date_after])
      |> Phoenix.Component.to_form(as: :filters)

    (&NewInputs.input/1)
    |> render_component(%{field: form[:date_after], type: "local-datetime"})
    |> Floki.parse_fragment!()
  end

  describe "input/1 with type local-datetime" do
    test "submits UTC while the picker shows the browser's local time" do
      # 15:40 UTC is what a user an hour ahead picks as 16:40.
      doc = render_local_datetime(%{"date_after" => "2026-07-17T15:40:00Z"})

      assert [hidden] = Floki.find(doc, ~s(input[type="hidden"]))
      assert Floki.attribute(hidden, "name") == ["filters[date_after]"]
      assert Floki.attribute(hidden, "value") == ["2026-07-17T15:40:00Z"]

      assert [picker] = Floki.find(doc, ~s(input[type="datetime-local"]))

      assert Floki.attribute(picker, "name") == [],
             "the picker holds wall-clock time and must not be submitted"

      assert [container] = Floki.find(doc, ~s([phx-hook="LocalDateTimeInput"]))

      assert Floki.attribute(container, "data-hidden-el") ==
               Floki.attribute(hidden, "id")

      assert Floki.attribute(container, "data-local-el") ==
               Floki.attribute(picker, "id")
    end

    test "renders no value when the filter is unset" do
      doc = render_local_datetime(%{})

      assert [hidden] = Floki.find(doc, ~s(input[type="hidden"]))
      assert Floki.attribute(hidden, "value") == []
    end
  end

  # ---- old_error/1 (CoreComponents) -----------------------------------------

  describe "old_error/1 used_input? gating" do
    test "unused field does not render error messages" do
      form = unused_field_form()

      html =
        render_component(&CoreComponents.old_error/1, %{
          field: form[:name]
        })

      refute html =~ "data-tag=\"error_message\""
      refute html =~ "can&#39;t be blank"
    end

    test "used field renders error messages" do
      form = used_field_form()

      html =
        render_component(&CoreComponents.old_error/1, %{
          field: form[:name]
        })

      assert html =~ "data-tag=\"error_message\""
      assert html =~ "can&#39;t be blank"
    end
  end
end
