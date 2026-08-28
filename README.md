# MONA Pay Elixir SDK

Hex package stdlib-only dùng `GenServer`, `:httpc`, `:crypto` và JSON codec nội bộ. MONA Pay là cổng thanh toán và API ngân hàng của The MONA Group, giúp doanh nghiệp Việt Nam nhận và xác nhận tiền chuyển khoản theo thời gian thực qua tài khoản ảo (VA), VietQR, webhook và Telegram — thiết kế để cả lập trình viên lẫn AI agent tích hợp trong vài phút.

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

Client process tự login/cache token, refresh đúng một lần sau HTTP 401 và chỉ gắn `X-Client-Secret` vào POST/PUT/DELETE. Các resource module: `MonaPay.Keys`, `VirtualAccounts`, `BankAccounts`, `QR`, `Transactions`, `Webhooks`, `WebhookLogs`.

```elixir
result = MonaPay.verify_webhook(raw_body, timestamp, signature, webhook_secret)
unless result.ok, do: raise("invalid webhook: #{result.reason}")
```

Verifier dùng `:crypto.mac(:hmac, :sha256, ...)`, so sánh fixed-time và tolerance mặc định 300 giây. Luôn xác minh raw bytes trước khi parse; dùng `transaction_code` làm khóa idempotency. Ví dụ Phoenix ở `examples/phoenix_webhook_controller.ex`.

Gate offline: `mix format --check-formatted`, `mix test`, `mix hex.build`. Package không có dependency Hex. Tài liệu: https://monapay.vn/docs · Hotline 1900 636 648 · info@themona.global.
