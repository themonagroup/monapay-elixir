defmodule MonaPayTest do
  use ExUnit.Case, async: true

  test "JSON codec giữ Unicode và nested values" do
    value = %{"name" => "MONA 🚀", "items" => [1, true, nil], "amount" => 2_500_000}

    assert {:ok, ^value} =
             value
             |> MonaPay.JSON.encode()
             |> IO.iodata_to_binary()
             |> MonaPay.JSON.decode()
  end

  test "client cache token, gắn secret và refresh đúng một lần" do
    {:ok, calls} = Agent.start_link(fn -> %{requests: [], logins: 0, me_calls: 0} end)

    transport = fn method, url, headers, body ->
      Agent.get_and_update(calls, fn state ->
        state = %{state | requests: state.requests ++ [{method, url, headers, body}]}

        cond do
          String.ends_with?(url, "/api/v1/oauth/token") ->
            count = state.logins + 1
            assert {:ok, %{"grant_type" => "client_credentials", "client_id" => "client-id", "client_secret" => "secret"}} = MonaPay.JSON.decode(body)

            response =
              %{"success" => true, "data" => %{"access_token" => "token-#{count}", "expires_in" => 3600}}
              |> MonaPay.JSON.encode()
              |> IO.iodata_to_binary()

            {{:ok, 200, response}, %{state | logins: count}}

          String.ends_with?(url, "/api/v1/client/me") and state.me_calls == 0 ->
            {{:ok, 401, ~s({"detail":"expired"})}, %{state | me_calls: 1}}

          true ->
            {{:ok, 200, ~s({"success":true,"data":{"id":"ok"}})}, state}
        end
      end)
    end

    {:ok, client} =
      MonaPay.start_link(
        client_id: "client-id",
        client_secret: "secret",
        base_url: "https://example.test",
        transport: transport
      )

    assert {:ok, %{"id" => "ok"}} = MonaPay.Webhooks.create(client, %{"name" => "Shop"})
    assert {:ok, %{"id" => "ok"}} = MonaPay.me(client)

    state = Agent.get(calls, & &1)
    assert state.logins == 2
    {_method, _url, post_headers, _body} = Enum.at(state.requests, 1)
    assert {"Authorization", "Bearer token-1"} in post_headers
    assert {"X-Client-Secret", "secret"} in post_headers
    {_method, _url, get_headers, _body} = List.last(state.requests)
    refute Enum.any?(get_headers, fn {name, _value} -> name == "X-Client-Secret" end)
    assert {"Authorization", "Bearer token-2"} in get_headers
  end

  test "transaction stream phân trang và dừng tại since_id phía client" do
    {:ok, pages} = Agent.start_link(fn -> [] end)

    transport = fn _method, url, _headers, _body ->
      if String.ends_with?(url, "/api/v1/client/login") do
        {:ok, 200, ~s({"success":true,"data":{"access_token":"token"}})}
      else
        uri = URI.parse(url)
        query = URI.decode_query(uri.query)
        refute Map.has_key?(query, "since_id")
        Agent.update(pages, &(&1 ++ [query["page"]]))

        items =
          if query["page"] == "1",
            do: [%{"id" => "tx-3"}, %{"id" => "tx-2"}],
            else: [%{"id" => "tx-1"}]

        response =
          %{"success" => true, "data" => %{"data" => items, "last_page" => 2}}
          |> MonaPay.JSON.encode()
          |> IO.iodata_to_binary()

        {:ok, 200, response}
      end
    end

    {:ok, client} =
      MonaPay.start_link(
        username: "user",
        password: "pass",
        base_url: "https://example.test",
        transport: transport
      )

    ids =
      client
      |> MonaPay.Transactions.stream("MONA 01", limit: 2, since_id: "tx-1")
      |> Enum.map(& &1["id"])

    assert ids == ["tx-3", "tx-2"]
    assert Agent.get(pages, & &1) == ["1", "2"]
  end

  test "webhook HMAC đúng, sai và quá hạn" do
    raw = ~s({"amount":2500000,"transaction_code":"FT1"})
    timestamp = System.system_time(:second) |> Integer.to_string()

    signature =
      "sha256=" <>
        Base.encode16(:crypto.mac(:hmac, :sha256, "test-secret", timestamp <> "." <> raw),
          case: :lower
        )

    assert %{ok: true, payload: %{"transaction_code" => "FT1"}} =
             MonaPay.verify_webhook(raw, timestamp, signature, "test-secret")

    assert %{ok: false, reason: :invalid_signature} =
             MonaPay.verify_webhook(
               raw,
               timestamp,
               "sha256=" <> String.duplicate("0", 64),
               "test-secret"
             )

    assert %{ok: false, reason: :timestamp_out_of_tolerance} =
             MonaPay.verify_webhook(
               raw,
               Integer.to_string(String.to_integer(timestamp) - 301),
               signature,
               "test-secret",
               300
             )
  end
end
