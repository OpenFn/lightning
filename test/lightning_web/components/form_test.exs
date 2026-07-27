defmodule LightningWeb.Components.FormTest do
  @moduledoc false
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias LightningWeb.Components.Form

  # A minimal embedded schema to produce real Ecto changesets for testing.
  defmodule Item do
    use Ecto.Schema

    embedded_schema do
      field :name, :string
      field :secret, :string
    end

    def changeset(item \\ %__MODULE__{}, params) do
      Ecto.Changeset.cast(item, params, [:name, :secret])
    end
  end

  defp form_for_item do
    Item.changeset(%{"name" => "test", "secret" => ""})
    |> Phoenix.Component.to_form()
  end

  describe "autocomplete" do
    test "renders autocomplete='off' by default" do
      form = form_for_item()

      html =
        render_component(&Form.text_field/1, %{
          form: form,
          field: :name
        })

      assert html =~ ~s(autocomplete="off")
    end

    test "allows explicit autocomplete override" do
      form = form_for_item()

      html =
        render_component(&Form.text_field/1, %{
          form: form,
          field: :name,
          autocomplete: "email"
        })

      assert html =~ ~s(autocomplete="email")
      refute html =~ ~s(autocomplete="off")
    end
  end
end
