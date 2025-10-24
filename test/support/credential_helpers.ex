defmodule Lightning.CredentialHelpers do
  def stub_oauth_client(oauth_client, response_kind) do
    endpoint = oauth_client.token_endpoint

    Mox.expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn
      %Tesla.Env{method: :post, url: ^endpoint} = env, _opts ->
        case response_kind do
          {200, body} when is_map(body) ->
            {:ok,
             %Tesla.Env{
               env
               | status: 200,
                 body: body
             }}

          429 ->
            {:ok,
             %Tesla.Env{
               env
               | status: 429,
                 body: %{"error" => "rate limit"}
             }}

          500 ->
            {:ok,
             %Tesla.Env{
               env
               | status: 500,
                 body: %{"error" => "internal_server_error"}
             }}
        end
    end)
  end
end
