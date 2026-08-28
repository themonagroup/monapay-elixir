defmodule MyAppWeb.MonaPayWebhookController do
  use MyAppWeb, :controller

  # Configure Plug.Parsers with a body_reader that stores the original bytes in
  # conn.assigns.raw_body. Re-encoding conn.body_params would break the HMAC.
  def create(conn, _params) do
    result =
      MonaPay.verify_webhook(
        conn.assigns.raw_body,
        get_req_header(conn, "x-mona-timestamp") |> List.first(),
        get_req_header(conn, "x-mona-signature") |> List.first(),
        System.fetch_env!("MONAPAY_WEBHOOK_SECRET")
      )

    if result.ok do
      transaction = result.payload
      # Insert with a UNIQUE constraint on transaction["transaction_code"].
      _ = transaction
      send_resp(conn, 200, "ok")
    else
      send_resp(conn, 401, "invalid webhook")
    end
  end
end
