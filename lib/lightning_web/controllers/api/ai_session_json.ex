defmodule LightningWeb.API.AiSessionJSON do
  @moduledoc false
  use LightningWeb, :verified_routes

  import LightningWeb.API.Helpers

  def render("index.json", %{page: page, filters: filters, conn: conn}) do
    %{
      data: Enum.map(page.entries, &resource(conn, &1, nil)),
      included: [],
      links: pagination_links(conn, page, filters)
    }
  end

  def render("show.json", %{session: session, conn: conn}) do
    %{
      data: resource(conn, session, session.messages),
      included: [],
      links: %{self: session_url(conn, session.id)}
    }
  end

  def render("message.json", %{
        message: message,
        session_id: session_id,
        conn: conn
      }) do
    %{
      data: %{
        type: "ai_messages",
        id: message.id,
        attributes: message(message),
        relationships: %{
          session: %{data: %{type: "ai_sessions", id: session_id}}
        },
        links: %{session: session_url(conn, session_id)}
      }
    }
  end

  # A list leaves the messages out and counts them; a single session carries
  # them and counts those.
  defp resource(conn, session, messages) do
    attributes =
      %{
        title: session.title,
        kind: kind(session.session_type),
        job_id: session.job_id || get_in(session.meta, ["unsaved_job", "id"]),
        workflow_id:
          session.workflow_id || get_in(session.meta, ["unsaved_workflow", "id"]),
        message_count:
          if(messages, do: length(messages), else: session.message_count),
        inserted_at: session.inserted_at,
        updated_at: session.updated_at
      }
      |> then(fn attributes ->
        if messages,
          do: Map.put(attributes, :messages, Enum.map(messages, &message/1)),
          else: attributes
      end)

    %{
      type: "ai_sessions",
      id: session.id,
      attributes: attributes,
      relationships: %{},
      links: %{self: session_url(conn, session.id)}
    }
  end

  defp message(message) do
    %{
      id: message.id,
      role: to_string(message.role),
      content: message.content,
      code: message.code,
      status: to_string(message.status),
      inserted_at: message.inserted_at
    }
  end

  defp kind("workflow_template"), do: "workflow"
  defp kind(kind), do: kind

  defp session_url(conn, id), do: url(conn, ~p"/api/ai_sessions/#{id}")
end
