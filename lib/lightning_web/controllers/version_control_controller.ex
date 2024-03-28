defmodule LightningWeb.VersionControlController do
  use LightningWeb, :controller

  def index(conn, _params) do
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
