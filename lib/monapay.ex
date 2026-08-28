defmodule MonaPay.Error do
  defexception [:message, :status, :body]
end

defmodule MonaPay do
  @moduledoc "Client process stdlib-only cho MONA Pay."

  use GenServer

  @default_base_url "https://api.monapay.vn"
  @call_timeout 45_000

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  def child_spec(options) do
    %{id: {__MODULE__, Keyword.get(options, :name, make_ref())}, start: {__MODULE__, :start_link, [options]}}
  end

  def login(client), do: GenServer.call(client, :login, @call_timeout)
  def me(client), do: call(client, :get, "/api/v1/client/me")

  def generate_key(client, name \\ "Default Key"),
    do: call(client, :post, "/api/v1/client-keys/generate", %{"name" => name})

  def list_keys(client), do: call(client, :get, "/api/v1/client-keys/list")

  def destroy_key(client, key_id),
    do: call(client, :delete, "/api/v1/client-keys/destroy/#{segment(key_id)}")

  def bank_accounts(client), do: call(client, :get, "/api/v1/client/bank-accounts")

  def register_virtual_account(client, body),
    do: call(client, :post, "/api/v1/acb/virtual-account/registration", body)

  def verify_virtual_account(client, request_id, code),
    do:
      call(client, :post, "/api/v1/acb/#{segment(request_id)}/virtual-account/verification", %{
        "code" => code
      })

  def register_notification(client, virtual_account_id, body \\ %{}),
    do:
      call(client, :post, "/api/v1/acb/#{segment(virtual_account_id)}/notification/registration", body)

  def verify_notification(client, request_id, code),
    do:
      call(client, :post, "/api/v1/acb/#{segment(request_id)}/notification/verification", %{
        "code" => code
      })

  def list_virtual_accounts(client, bank_account_id),
    do: call(client, :get, "/api/v1/acb/#{segment(bank_account_id)}/virtual-account/retrieve")

  def generate_qr(client, body), do: call(client, :post, "/api/v1/acb/qr-payment/generate", body)

  def cancel_qr(client, qr_code_id, body \\ nil),
    do: call(client, :delete, "/api/v1/acb/qr-payment/#{segment(qr_code_id)}/cancellation", body)

  def list_transactions(client, virtual_account_number, options \\ []) do
    if to_string_or_empty(virtual_account_number) == "" do
      raise ArgumentError, "virtual_account_number là bắt buộc"
    end

    query = [
      virtual_account_number: virtual_account_number,
      page: positive(options[:page], 1),
      limit: positive(options[:limit], 100)
    ]

    call(client, :get, "/api/v1/acb/virtual-account/transactions", nil, query)
  end

  def stream_transactions(client, virtual_account_number, options \\ []) do
    first_page = positive(options[:page], 1)
    limit = positive(options[:limit], 100)
    since_id = options[:since_id] && to_string(options[:since_id])

    Stream.resource(
      fn -> {first_page, false} end,
      fn
        state = {_page, true} ->
          {:halt, state}

        {page, false} ->
          case list_transactions(client, virtual_account_number, page: page, limit: limit) do
            {:ok, response} when is_map(response) ->
              items = if is_list(response["data"]), do: response["data"], else: []
              {selected, checkpoint_found} = take_until_checkpoint(items, since_id)

              done =
                checkpoint_found or
                  case Map.fetch(response, "has_next") do
                    {:ok, has_next} -> not has_next
                    :error -> page >= integer(response["last_page"], page)
                  end

              {selected, {page + 1, done}}

            {:ok, response} ->
              raise MonaPay.Error, message: "Response giao dịch không phải object", body: response

            {:error, error} ->
              raise error
          end
      end,
      fn _state -> :ok end
    )
  end

  def retry_transaction(client, transaction_id, target_type, target_id \\ nil) do
    body = %{"target_type" => target_type}
    body = if target_id in [nil, ""], do: body, else: Map.put(body, "target_id", target_id)

    call(
      client,
      :post,
      "/api/v1/acb/virtual-account/transactions/#{segment(transaction_id)}/retry",
      body
    )
  end

  def list_webhooks(client), do: call(client, :get, "/api/v1/client-webhooks")
  def create_webhook(client, body), do: call(client, :post, "/api/v1/client-webhooks", body)

  def update_webhook(client, config_id, body),
    do: call(client, :put, "/api/v1/client-webhooks/#{segment(config_id)}", body)

  def remove_webhook(client, config_id),
    do: call(client, :delete, "/api/v1/client-webhooks/#{segment(config_id)}")

  def test_webhook(client, body \\ %{"is_dummy" => true}),
    do: call(client, :post, "/api/v1/client-webhooks/test", body)

  def list_webhook_logs(client, options \\ []),
    do: call(client, :get, "/api/v1/webhook-logs", nil, log_query(options))

  def webhook_log_stats(client, options \\ []),
    do: call(client, :get, "/api/v1/webhook-logs/stats", nil, log_query(options))

  def verify_webhook(raw, timestamp, signature, secret, tolerance \\ 300),
    do: MonaPay.Webhook.verify_webhook(raw, timestamp, signature, secret, tolerance)

  defp call(client, method, path, body \\ nil, query \\ []),
    do: GenServer.call(client, {:request, method, path, body, query}, @call_timeout)

  @impl true
  def init(options) do
    username = options[:username] |> to_string_or_empty()
    password = options[:password] |> to_string_or_empty()
    base_url = options[:base_url] || @default_base_url
    transport = options[:transport] || &MonaPay.HTTPTransport.send/4

    cond do
      String.trim(username) == "" -> {:stop, "username là bắt buộc"}
      password == "" -> {:stop, "password là bắt buộc"}
      not valid_base_url?(base_url) -> {:stop, "base_url phải là URL http/https hợp lệ"}
      not is_function(transport, 4) -> {:stop, "transport phải là function arity 4"}
      true ->
        {:ok,
         %{
           username: username,
           password: password,
           client_secret: to_string_or_empty(options[:client_secret]),
           base_url: String.trim_trailing(base_url, "/"),
           token: nil,
           transport: transport
         }}
    end
  end

  @impl true
  def handle_call(:login, _from, state) do
    case ensure_login(state) do
      {:ok, token, new_state} -> {:reply, {:ok, token}, new_state}
      {:error, error, new_state} -> {:reply, {:error, error}, new_state}
    end
  end

  def handle_call({:request, method, path, body, query}, _from, state) do
    case request_with_refresh(state, method, path, body, query) do
      {:ok, data, new_state} ->
        {:reply, {:ok, data}, maybe_capture_secret(new_state, path, data)}

      {:error, error, new_state} ->
        {:reply, {:error, error}, new_state}
    end
  end

  defp request_with_refresh(state, method, path, body, query) do
    with {:ok, token, logged_in} <- ensure_login(state) do
      case send_request(logged_in, method, path, body, query, token, true) do
        {:error, %MonaPay.Error{status: 401}} ->
          expired = %{logged_in | token: nil}

          case ensure_login(expired) do
            {:ok, refreshed, refreshed_state} ->
              case send_request(refreshed_state, method, path, body, query, refreshed, true) do
                {:ok, data} -> {:ok, data, refreshed_state}
                {:error, error} -> {:error, error, refreshed_state}
              end

            {:error, error, failed_state} ->
              {:error, error, failed_state}
          end

        {:ok, data} ->
          {:ok, data, logged_in}

        {:error, error} ->
          {:error, error, logged_in}
      end
    end
  end

  defp ensure_login(%{token: token} = state) when is_binary(token) and token != "",
    do: {:ok, token, state}

  defp ensure_login(state) do
    body = %{"username" => state.username, "password" => state.password}

    case send_request(state, :post, "/api/v1/client/login", body, [], nil, false) do
      {:ok, %{"access_token" => token}} when is_binary(token) and token != "" ->
        {:ok, token, %{state | token: token}}

      {:ok, data} ->
        {:error, %MonaPay.Error{message: "Response đăng nhập không có access_token", body: data}, state}

      {:error, error} ->
        {:error, error, state}
    end
  end

  defp send_request(state, method, path, body, query, token, authenticated) do
    query =
      query
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Enum.into(%{}, fn {key, value} -> {to_string(key), to_string(value)} end)

    suffix = if map_size(query) == 0, do: "", else: "?" <> URI.encode_query(query)
    url = state.base_url <> path <> suffix
    raw_body = if is_nil(body), do: nil, else: body |> MonaPay.JSON.encode() |> IO.iodata_to_binary()
    headers = [{"Accept", "application/json"}]
    headers = if raw_body, do: [{"Content-Type", "application/json"} | headers], else: headers
    headers = if authenticated, do: [{"Authorization", "Bearer " <> token} | headers], else: headers

    headers =
      if authenticated and method != :get and state.client_secret != "" do
        [{"X-Client-Secret", state.client_secret} | headers]
      else
        headers
      end

    case state.transport.(method, url, headers, raw_body) do
      {:ok, status, raw} -> parse_response(status, raw)
      {:error, reason} -> {:error, %MonaPay.Error{message: "Không kết nối được MONA Pay: #{inspect(reason)}"}}
      other -> {:error, %MonaPay.Error{message: "Transport trả response không hợp lệ: #{inspect(other)}"}}
    end
  rescue
    error -> {:error, %MonaPay.Error{message: "Không gửi được request MONA Pay: #{Exception.message(error)}"}}
  end

  defp parse_response(status, raw) when is_integer(status) and is_binary(raw) do
    decoded = if raw == "", do: {:ok, %{}}, else: MonaPay.JSON.decode(raw)

    case decoded do
      {:ok, envelope} when is_map(envelope) ->
        if status < 200 or status >= 300 or envelope["success"] == false do
          message = envelope["message"] || envelope["detail"] || "MONA Pay API lỗi HTTP #{status}"
          {:error, %MonaPay.Error{message: message, status: status, body: envelope}}
        else
          {:ok, envelope["data"]}
        end

      _ ->
        {:error,
         %MonaPay.Error{
           message: "MONA Pay trả response không phải JSON (HTTP #{status})",
           status: status,
           body: raw
         }}
    end
  end

  defp maybe_capture_secret(state, "/api/v1/client-keys/generate", %{"client_secret" => secret})
       when is_binary(secret) and secret != "",
       do: %{state | client_secret: secret}

  defp maybe_capture_secret(state, _path, _data), do: state

  defp log_query(options) do
    [
      status: options[:status],
      from_date: options[:from_date],
      to_date: options[:to_date],
      page: options[:page],
      limit: options[:limit]
    ]
  end

  defp take_until_checkpoint(items, nil), do: {items, false}

  defp take_until_checkpoint(items, checkpoint) do
    selected = Enum.take_while(items, &(not transaction_matches?(&1, checkpoint)))
    {selected, length(selected) < length(items)}
  end

  defp transaction_matches?(item, checkpoint) when is_map(item),
    do: to_string_or_empty(item["id"]) == checkpoint or to_string_or_empty(item["transaction_code"]) == checkpoint

  defp transaction_matches?(_item, _checkpoint), do: false
  defp segment(value), do: URI.encode(to_string(value), &URI.char_unreserved?/1)
  defp positive(value, _fallback) when is_integer(value) and value > 0, do: value
  defp positive(_value, fallback), do: fallback
  defp integer(value, _fallback) when is_integer(value), do: value
  defp integer(_value, fallback), do: fallback
  defp to_string_or_empty(nil), do: ""
  defp to_string_or_empty(value), do: to_string(value)

  defp valid_base_url?(value) when is_binary(value) do
    uri = URI.parse(value)
    uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != ""
  end

  defp valid_base_url?(_value), do: false
end
