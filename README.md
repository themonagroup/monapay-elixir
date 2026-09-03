# MONA Pay Elixir SDK

Hex package stdlib-only dùng `GenServer`, `:httpc`, `:crypto` và JSON codec nội bộ. MONA Pay là cổng thanh toán và API ngân hàng của The MONA Group, giúp doanh nghiệp Việt Nam nhận và xác nhận tiền chuyển khoản theo thời gian thực qua tài khoản ảo (VA), VietQR, webhook và Telegram, thiết kế để cả lập trình viên lẫn AI agent tích hợp trong vài phút.

## Xác thực cho AI agent

```bash
export MONAPAY_CLIENT_ID="client-id"
export MONAPAY_CLIENT_SECRET="client-secret"
export MONAPAY_BASE_URL="https://api.monapay.vn"
```

```elixir
{:ok, client} = MonaPay.from_env()
{:ok, profile} = MonaPay.me(client)
{:ok, qr} = MonaPay.QR.generate(client, qr_body)
{:ok, sandbox} = MonaPay.Sandbox.create_transaction(client, %{"virtual_account_number" => "MONA123", "amount" => 10_000, "description" => "AI test"})
IO.inspect(profile)
```

`MonaPay.from_env/1` ưu tiên client credentials, cache token tới gần hạn và tự lấy lại khi gặp HTTP 401. Username/password chỉ là fallback tương thích cũ, không dùng cho AI agent vì sẽ gãy khi bật 2FA.

```elixir
{:ok, client} = MonaPay.start_link(
  username: System.fetch_env!("MONAPAY_USERNAME"),
  password: System.fetch_env!("MONAPAY_PASSWORD"),
  client_secret: System.get_env("MONAPAY_CLIENT_SECRET")
)

{:ok, profile} = MonaPay.me(client)

client
|> MonaPay.Transactions.stream("MONA123")
|> Enum.each(&IO.inspect(&1["transaction_code"]))
```

Client process cache token theo hạn, refresh đúng một lần sau HTTP 401 và chỉ gắn `X-Client-Secret` vào POST/PUT/DELETE. Các resource module gồm `Keys`, `VirtualAccounts`, `BankAccounts`, `QR`, `Transactions`, `Webhooks`, `WebhookLogs`, `Sandbox`, `EmailConfigs`, `EmailLogs`, `EmailSuppressions` dưới namespace `MonaPay`.

```elixir
result = MonaPay.verify_webhook(raw_body, timestamp, signature, webhook_secret)
unless result.ok, do: raise("invalid webhook: #{result.reason}")
```

Verifier dùng `:crypto.mac(:hmac, :sha256, ...)`, so sánh fixed-time và tolerance mặc định 300 giây. Luôn xác minh raw bytes trước khi parse; dùng `transaction_code` làm khóa idempotency. Ví dụ Phoenix ở `examples/phoenix_webhook_controller.ex`.

Gate offline: `mix format --check-formatted`, `mix test`, `mix hex.build`. Package không có dependency Hex. Tài liệu: https://monapay.vn/docs · Hotline 1900 636 648 · info@themona.global.
