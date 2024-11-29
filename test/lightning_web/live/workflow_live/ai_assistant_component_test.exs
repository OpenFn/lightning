defmodule LightningWeb.WorkflowLive.AiAssistantComponentTest do
  alias LightningWeb.WorkflowLive.AiAssistantComponent
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

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

    openfn_link =
      Enum.find(
        links,
        &(Floki.attribute(&1, "href") == ["https://github.com/OpenFn/apollo"])
      )

    assert openfn_link != nil

    assert Floki.attribute(openfn_link, "class") == [
             "text-primary-400 hover:text-primary-600"
           ]

    assert Floki.attribute(openfn_link, "target") == ["_blank"]

    docs_link =
      Enum.find(
        links,
        &(Floki.attribute(&1, "href") == [
            "https://github.com/OpenFn/lightning"
          ])
      )

    assert docs_link != nil

    assert Floki.attribute(docs_link, "class") == [
             "text-primary-400 hover:text-primary-600"
           ]

    assert Floki.attribute(docs_link, "target") == ["_blank"]

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

    text = Floki.text(parsed_html)
    assert text =~ "Unclosed div"
    assert text =~ "Unclosed span"
    assert text =~ "Some text"
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
