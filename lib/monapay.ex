defmodule MonaPay.Error do
  defexception [:message, :status, :body]
end

defmodule MonaPay do
  @moduledoc "Client process stdlib-only cho MONA Pay."

  use GenServer

  @default_base_url "https://api.monapay.vn"
  @call_timeout 45_000

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  def from_env(options \\ []) do
    start_link(
      Keyword.merge(
        [
          client_id: System.get_env("MONAPAY_CLIENT_ID"),
          client_secret: System.get_env("MONAPAY_CLIENT_SECRET"),
          username: System.get_env("MONAPAY_USERNAME"),
          password: System.get_env("MONAPAY_PASSWORD"),
          base_url: System.get_env("MONAPAY_BASE_URL") || @default_base_url
        ],
        options
      )
    )
  end

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

  def reveal_key(client, key_id, confirmation),
    do: call(client, :post, "/api/v1/client-keys/#{segment(key_id)}/reveal", confirmation)

  def rotate_key(client, key_id),
    do: call(client, :post, "/api/v1/client-keys/#{segment(key_id)}/rotate", %{})

  def bank_accounts(client), do: call(client, :get, "/api/v1/client/bank-accounts")

  def get_payment_profile(client), do: call(client, :get, "/api/v1/payment-profile")
  def set_payment_profile(client, body), do: call(client, :put, "/api/v1/payment-profile", body)

  def rotate_return_secret(client),
    do: call(client, :post, "/api/v1/payment-profile/rotate-return-secret", %{})

  def reveal_return_secret(client, confirmation),
    do: call(client, :post, "/api/v1/payment-profile/reveal-return-secret", confirmation)

  def create_checkout(client, body, options \\ []) do
    key = options[:idempotency_key] || idempotency_key()
    call(client, :post, "/api/v1/checkouts", body, [], [{"Idempotency-Key", key}])
  end

  def get_checkout(client, checkout_id),
    do: call(client, :get, "/api/v1/checkouts/#{segment(checkout_id)}")

  def list_checkouts(client, options \\ []) do
    query = Keyword.take(options, [:status, :order_code, :from_date, :to_date, :page, :limit])
    call(client, :get, "/api/v1/checkouts", nil, query)
  end

  def cancel_checkout(client, checkout_id, options \\ []) do
    key = options[:idempotency_key] || idempotency_key()
    call(client, :post, "/api/v1/checkouts/#{segment(checkout_id)}/cancel", %{}, [], [{"Idempotency-Key", key}])
  end

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

  def create_sandbox_transaction(client, body),
    do: call(client, :post, "/api/v1/sandbox/transactions", body)

  def list_email_configs(client), do: call(client, :get, "/api/v1/email-configs")
  def create_email_config(client, body), do: call(client, :post, "/api/v1/email-configs", body)
  def get_email_config(client, id), do: call(client, :get, "/api/v1/email-configs/#{segment(id)}")
  def update_email_config(client, id, body), do: call(client, :put, "/api/v1/email-configs/#{segment(id)}", body)
  def remove_email_config(client, id), do: call(client, :delete, "/api/v1/email-configs/#{segment(id)}")

  def verify_email_config(client, id, email, code),
    do: call(client, :post, "/api/v1/email-configs/#{segment(id)}/verify", %{"email" => email, "code" => code})

  def resend_email_verification(client, id, email),
    do: call(client, :post, "/api/v1/email-configs/#{segment(id)}/resend-verification", %{"email" => email})

  def test_email_config(client, id),
    do: call(client, :post, "/api/v1/email-configs/#{segment(id)}/test", %{})

  def list_email_logs(client, options \\ []),
    do: call(client, :get, "/api/v1/email-logs", nil, email_log_query(options))

  def email_log_stats(client, options \\ []),
    do: call(client, :get, "/api/v1/email-logs/stats", nil, Keyword.take(options, [:from_date, :to_date]))

  def list_email_suppressions(client), do: call(client, :get, "/api/v1/email-suppressions")
  def remove_email_suppression(client, email), do: call(client, :delete, "/api/v1/email-suppressions/#{segment(email)}")

  def verify_webhook(raw, timestamp, signature, secret, tolerance \\ 300),
    do: MonaPay.Webhook.verify_webhook(raw, timestamp, signature, secret, tolerance)

  defp call(client, method, path, body \\ nil, query \\ [], headers \\ []),
    do: GenServer.call(client, {:request, method, path, body, query, headers}, @call_timeout)

  @impl true
  def init(options) do
    username = options[:username] |> to_string_or_empty()
    password = options[:password] |> to_string_or_empty()
    client_id = options[:client_id] |> to_string_or_empty()
    client_secret = options[:client_secret] |> to_string_or_empty()
    base_url = options[:base_url] || @default_base_url
    transport = options[:transport] || &MonaPay.HTTPTransport.send/4

    cond do
      (String.trim(client_id) == "" or client_secret == "") and (String.trim(username) == "" or password == "") ->
        {:stop, "Cần client ID + client secret hoặc username + password; không dùng password cho AI agent vì sẽ gãy khi bật 2FA"}
      not valid_base_url?(base_url) -> {:stop, "base_url phải là URL http/https hợp lệ"}
      not is_function(transport, 4) -> {:stop, "transport phải là function arity 4"}
      true ->
        {:ok,
         %{
           username: username,
           password: password,
           client_id: client_id,
           client_secret: client_secret,
           base_url: String.trim_trailing(base_url, "/"),
           token: nil,
           token_expires_at: 0,
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

  def handle_call({:request, method, path, body, query, headers}, _from, state) do
    case request_with_refresh(state, method, path, body, query, headers) do
      {:ok, data, new_state} ->
        {:reply, {:ok, data}, maybe_capture_secret(new_state, path, data)}

      {:error, error, new_state} ->
        {:reply, {:error, error}, new_state}
    end
  end

  defp request_with_refresh(state, method, path, body, query, headers) do
    with {:ok, token, logged_in} <- ensure_login(state) do
      case send_request(logged_in, method, path, body, query, token, true, headers) do
        {:error, %MonaPay.Error{status: 401}} ->
          expired = %{logged_in | token: nil, token_expires_at: 0}

          case ensure_login(expired) do
            {:ok, refreshed, refreshed_state} ->
              case send_request(refreshed_state, method, path, body, query, refreshed, true, headers) do
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

  defp ensure_login(%{token: token, token_expires_at: expires_at} = state)
       when is_binary(token) and token != "" do
    if System.system_time(:second) < expires_at,
      do: {:ok, token, state},
      else: perform_login(%{state | token: nil, token_expires_at: 0})
  end

  defp ensure_login(state), do: perform_login(state)

  defp perform_login(state) do
    using_client_credentials = state.client_id != "" and state.client_secret != ""

    body =
      if using_client_credentials,
        do: %{"grant_type" => "client_credentials", "client_id" => state.client_id, "client_secret" => state.client_secret},
        else: %{"username" => state.username, "password" => state.password}

    path = if using_client_credentials, do: "/api/v1/oauth/token", else: "/api/v1/client/login"

    case send_request(state, :post, path, body, [], nil, false) do
      {:ok, %{"access_token" => token} = data} when is_binary(token) and token != "" ->
        expires_in = integer(data["expires_in"], if(using_client_credentials, do: 3600, else: 86_400))
        {:ok, token, %{state | token: token, token_expires_at: System.system_time(:second) + max(expires_in - 60, 0)}}

      {:ok, data} ->
        {:error, %MonaPay.Error{message: "Response đăng nhập không có access_token", body: data}, state}

      {:error, error} ->
        {:error, error, state}
    end
  end

  defp send_request(state, method, path, body, query, token, authenticated, custom_headers \\ []) do
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

    headers = custom_headers ++ headers

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

  defp maybe_capture_secret(state, path, %{"client_secret" => secret})
       when is_binary(secret) and secret != "" do
    if String.ends_with?(path, "/rotate"), do: %{state | client_secret: secret}, else: state
  end

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

  defp email_log_query(options) do
    [
      config_id: options[:config_id], status: options[:status], event_type: options[:event_type],
      from_date: options[:from_date], to_date: options[:to_date], page: options[:page], limit: options[:limit]
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
  defp idempotency_key do
    <<a::binary-size(4), b::binary-size(2), c0, c1, d0, d1, e::binary-size(6)>> = :crypto.strong_rand_bytes(16)
    c = <<rem(c0, 16) + 64, c1>>
    d = <<rem(d0, 64) + 128, d1>>
    Enum.map_join([a, b, c, d, e], "-", &Base.encode16(&1, case: :lower))
  end
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
