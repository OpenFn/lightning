defmodule LightningWeb.OauthController do
  use LightningWeb, :controller
  alias Lightning.VersionControl

  plug :fetch_current_user

  def new(conn, %{"provider" => "github", "code" => code}) do
    if user = conn.assigns.current_user do
      case VersionControl.fetch_github_oauth_token(code) do
        {:ok, token} ->
          VersionControl.save_github_oauth_token(user, token)

        {:error, reason} ->
          VersionControl.Events.oauth_token_failed(user, reason)
      end
    end

    html(conn, """
      <html>
        <body>
          <script type="text/javascript">
            window.onload = function() {
              window.close();
            }
          </script>
        </body>
      </html>
    """)
  end
end
