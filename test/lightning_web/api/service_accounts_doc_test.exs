defmodule LightningWeb.API.ServiceAccountsDocTest do
  use Lightning.DataCase, async: true

  import Lightning.ServiceAccountHelpers

  alias Lightning.ServiceAccount
  alias Lightning.ServiceAccount.AccessToken
  alias Lightning.ServiceAccount.Assertion
  alias LightningWeb.TokenEndpointError

  @doc_path Path.expand("../../../SERVICE_ACCOUNTS.md", __DIR__)

  defp section(heading) do
    @doc_path
    |> File.read!()
    |> String.split(~r/^(?=\#{2,3} )/m)
    |> Enum.find_value(fn part ->
      case String.split(part, "\n", parts: 2) do
        ["## " <> ^heading, body] -> body
        ["### " <> ^heading, body] -> body
        _ -> nil
      end
    end) || raise "SERVICE_ACCOUNTS.md has no heading #{inspect(heading)}"
  end

  defp script(name) do
    case Regex.run(
           ~r/```js\n(\/\/ #{Regex.escape(name)}:.*?)```/s,
           File.read!(@doc_path),
           capture: :all_but_first
         ) do
      [source] -> source
      nil -> raise "SERVICE_ACCOUNTS.md has no js block starting // #{name}:"
    end
  end

  defp first_column(text) do
    ~r/^\| `([a-z_:]+)` +\|/m
    |> Regex.scan(text, capture: :all_but_first)
    |> MapSet.new(fn [cell] -> cell end)
  end

  defp run_script(tmp_dir, name, args) do
    path = Path.join(tmp_dir, name)
    File.write!(path, script(name))
    System.cmd("node", [path | args], stderr_to_stdout: true)
  end

  defp write_pem(tmp_dir, file, jwk) do
    {_, pem} = JOSE.JWK.to_pem(jwk)
    path = Path.join(tmp_dir, file)
    File.write!(path, pem)
    path
  end

  @tag :tmp_dir
  test "service_account_id.mjs prints the id Lightning computes", %{
    tmp_dir: tmp_dir
  } do
    public_key = JOSE.JWK.generate_key({:rsa, 2048}) |> JOSE.JWK.to_public()

    {:ok, account} =
      public_key |> JOSE.JWK.to_pem() |> elem(1) |> ServiceAccount.from_pem()

    {output, status} =
      run_script(tmp_dir, "service_account_id.mjs", [
        write_pem(tmp_dir, "sa_public.pem", public_key)
      ])

    assert {status, String.trim(output)} == {0, account.id}
  end

  @tag :tmp_dir
  test "make_assertion.mjs signs an assertion Lightning accepts", %{
    tmp_dir: tmp_dir
  } do
    {account, private_key} = service_account_with_key()
    Mox.stub(Lightning.MockConfig, :service_account, fn -> account end)
    audience = LightningWeb.Endpoint.url() <> "/api/oauth/token"

    {output, 0} =
      run_script(tmp_dir, "make_assertion.mjs", [
        write_pem(tmp_dir, "sa_private.pem", private_key),
        audience
      ])

    assert Assertion.verify(output, audience, nil) == {:ok, account}
  end

  test "the Token grants table lists every grant and nothing else" do
    assert first_column(section("Token grants")) ==
             MapSet.new(AccessToken.scopes())
  end

  test "the refusals table matches what the token endpoint sends" do
    doc_rows =
      ~r/^\| (\d{3}) +\| `([a-z_]+)` +\| `([^`]+)` +\| (?:`([a-z_]+)`)? *\|$/m
      |> Regex.scan(section("When the exchange is refused"),
        capture: :all_but_first
      )
      |> MapSet.new(fn
        [status, error, description] ->
          {status, error, description, ""}

        [status, error, description, reason] ->
          {status, error, description, reason}
      end)

    sent_rows =
      MapSet.new(TokenEndpointError.reasons(), fn reason ->
        conn = TokenEndpointError.respond(Phoenix.ConnTest.build_conn(), reason)
        body = Jason.decode!(conn.resp_body)

        # OAuth allows no " or \ in an error_description.
        assert body["error_description"] =~
                 ~r/\A[\x20-\x21\x23-\x5B\x5D-\x7E]+\z/

        log_reason =
          if reason in Assertion.errors(), do: to_string(reason), else: ""

        {to_string(conn.status), body["error"], body["error_description"],
         log_reason}
      end)

    assert doc_rows == sent_rows
  end
end
