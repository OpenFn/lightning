defmodule LightningWeb.WorkflowLive.AiAssistantComponentTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias LightningWeb.WorkflowLive.AiAssistantComponent

  describe "formatted_content/1" do
    test "renders assistant messages with properly styled links" do
      content = """
      Here are some links:
      - [Apollo Repo](https://github.com/OpenFn/apollo)
      - Plain text
      - [Lightning Repo](https://github.com/OpenFn/lightning)
      """

      html =
        render_component(&AiAssistantComponent.formatted_content/1,
          content: content
        )

      parsed_html = Floki.parse_document!(html)
      links = Floki.find(parsed_html, "a")

      apollo_link =
        Enum.find(
          links,
          &(Floki.attribute(&1, "href") == ["https://github.com/OpenFn/apollo"])
        )

      assert apollo_link != nil

      assert Floki.attribute(apollo_link, "class") == [
               "text-primary-400 hover:text-primary-600"
             ]

      assert Floki.attribute(apollo_link, "target") == ["_blank"]

      lightning_link =
        Enum.find(
          links,
          &(Floki.attribute(&1, "href") == [
              "https://github.com/OpenFn/lightning"
            ])
        )

      assert lightning_link != nil

      assert Floki.attribute(lightning_link, "class") == [
               "text-primary-400 hover:text-primary-600"
             ]

      assert Floki.attribute(lightning_link, "target") == ["_blank"]

      list_items = Floki.find(parsed_html, "li")

      assert Enum.any?(list_items, fn li ->
               Floki.text(li) |> String.trim() == "Plain text"
             end)
    end

    test "handles content with invalid markdown links" do
      content = """
      Broken [link(test.com
      [Another](working.com)
      """

      html =
        render_component(&AiAssistantComponent.formatted_content/1,
          content: content
        )

      parsed_html = Floki.parse_document!(html)
      assert Floki.text(parsed_html) =~ "Broken [link(test.com"

      working_link =
        Floki.find(parsed_html, "a")
        |> Enum.find(&(Floki.attribute(&1, "href") == ["working.com"]))

      assert working_link != nil

      assert Floki.attribute(working_link, "class") == [
               "text-primary-400 hover:text-primary-600"
             ]

      assert Floki.attribute(working_link, "target") == ["_blank"]
    end

    test "elements without defined styles remain unchanged" do
      content = """
      <weirdo>Some code</weirdo>
      <pierdo>Preformatted text</pierdo>
      [A link](https://weirdopierdo.com)
      """

      html =
        render_component(&AiAssistantComponent.formatted_content/1,
          content: content
        )

      parsed_html = Floki.parse_document!(html)

      code = Floki.find(parsed_html, "weirdo")
      pre = Floki.find(parsed_html, "pierdo")
      assert Floki.attribute(code, "class") == []
      assert Floki.attribute(pre, "class") == []

      link =
        Floki.find(parsed_html, "a")
        |> Enum.find(
          &(Floki.attribute(&1, "href") == ["https://weirdopierdo.com"])
        )

      assert link != nil

      assert Floki.attribute(link, "class") == [
               "text-primary-400 hover:text-primary-600"
             ]

      assert Floki.attribute(link, "target") == ["_blank"]
    end

    test "handles content that cannot be parsed as AST" do
      content = """
      <div>Unclosed div
      <span>Unclosed span
      Some text
      """

      html =
        render_component(&AiAssistantComponent.formatted_content/1,
          content: content
        )

      parsed_html = Floki.parse_document!(html)

      assert Floki.text(parsed_html) =~ "Unclosed div"
      assert Floki.text(parsed_html) =~ "Unclosed span"
      assert Floki.text(parsed_html) =~ "Some text"
    end

    test "applies styles to elements not defined in the default styles" do
      content = """
      <custom-tag>Custom styled content</custom-tag>
      """

      custom_attributes = %{
        "custom-tag" => %{class: "custom-class text-green-700"}
      }

      html =
        render_component(&AiAssistantComponent.formatted_content/1, %{
          content: content,
          attributes: custom_attributes
        })

      parsed_html = Floki.parse_document!(html)
      custom_tag = Floki.find(parsed_html, "custom-tag") |> hd()

      assert custom_tag != nil

      assert Floki.attribute(custom_tag, "class") == [
               "custom-class text-green-700"
             ]
    end
  end

  describe "error_message/1" do
    test "renders string error message" do
      assert AiAssistantComponent.error_message({:error, "Something went wrong"}) ==
               "Something went wrong"
    end

    test "renders changeset error message" do
      changeset = %Ecto.Changeset{
        valid?: false,
        errors: [content: {"is invalid", []}],
        data: %Lightning.AiAssistant.ChatSession{}
      }

      assert AiAssistantComponent.error_message({:error, changeset}) ==
               "Could not save message. Please try again."
    end

    test "renders text message from map" do
      error_data = %{text: "Specific error message"}

      assert AiAssistantComponent.error_message(
               {:error, :custom_reason, error_data}
             ) ==
               "Specific error message"
    end

    test "renders default error message for unhandled cases" do
      assert AiAssistantComponent.error_message({:error, :unknown_reason}) ==
               "Oops! Something went wrong. Please try again."

      assert AiAssistantComponent.error_message(:unexpected_error) ==
               "Oops! Something went wrong. Please try again."
    end
  end
end
