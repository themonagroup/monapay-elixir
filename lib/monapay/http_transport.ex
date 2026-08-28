defmodule MonaPay.HTTPTransport do
  @moduledoc false

  def send(method, url, headers, body) do
    request_headers =
      Enum.map(headers, fn {name, value} ->
        {String.to_charlist(name), String.to_charlist(value)}
      end)

    request =
      if body do
        {String.to_charlist(url), request_headers, 'application/json', body}
      else
        {String.to_charlist(url), request_headers}
      end

    options = [timeout: 30_000, connect_timeout: 10_000] ++ ssl_options(url)

    case :httpc.request(method, request, options, body_format: :binary) do
      {:ok, {{_version, status, _reason}, _response_headers, response_body}} ->
        {:ok, status, response_body}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ssl_options("https://" <> _rest) do
    verify = [
      verify: :verify_peer,
      depth: 5,
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]

    verify =
      cond do
        function_exported?(:public_key, :cacerts_get, 0) ->
          [{:cacerts, apply(:public_key, :cacerts_get, [])} | verify]

        cacertfile = system_cacertfile() ->
          [{:cacertfile, String.to_charlist(cacertfile)} | verify]

        true ->
          verify
      end

    [{:ssl, verify}]
  end

  defp ssl_options(_url), do: []

  defp system_cacertfile do
    [
      System.get_env("SSL_CERT_FILE"),
      "/etc/ssl/certs/ca-certificates.crt",
      "/etc/pki/tls/certs/ca-bundle.crt",
      "/etc/ssl/cert.pem"
    ]
    |> Enum.find(&(is_binary(&1) and File.regular?(&1)))
  end
end
