defmodule MonaPay.Keys do
  def generate(client, name \\ "Default Key"), do: MonaPay.generate_key(client, name)
  def list(client), do: MonaPay.list_keys(client)
  def destroy(client, key_id), do: MonaPay.destroy_key(client, key_id)
  def reveal(client, key_id, confirmation), do: MonaPay.reveal_key(client, key_id, confirmation)
  def rotate(client, key_id), do: MonaPay.rotate_key(client, key_id)
end

defmodule MonaPay.VirtualAccounts do
  def register(client, body), do: MonaPay.register_virtual_account(client, body)
  def verify(client, request_id, code), do: MonaPay.verify_virtual_account(client, request_id, code)

  def register_notification(client, virtual_account_id, body \\ %{}),
    do: MonaPay.register_notification(client, virtual_account_id, body)

  def verify_notification(client, request_id, code),
    do: MonaPay.verify_notification(client, request_id, code)

  def list(client, bank_account_id), do: MonaPay.list_virtual_accounts(client, bank_account_id)
end

defmodule MonaPay.BankAccounts do
  def list(client), do: MonaPay.bank_accounts(client)
end

defmodule MonaPay.PaymentProfile do
  def get(client), do: MonaPay.get_payment_profile(client)
  def set(client, body), do: MonaPay.set_payment_profile(client, body)
  def rotate_return_secret(client), do: MonaPay.rotate_return_secret(client)
  def reveal_return_secret(client, confirmation), do: MonaPay.reveal_return_secret(client, confirmation)
end

defmodule MonaPay.Checkouts do
  def create(client, body, options \\ []), do: MonaPay.create_checkout(client, body, options)
  def get(client, checkout_id), do: MonaPay.get_checkout(client, checkout_id)
  def list(client, options \\ []), do: MonaPay.list_checkouts(client, options)
  def cancel(client, checkout_id, options \\ []), do: MonaPay.cancel_checkout(client, checkout_id, options)
end

defmodule MonaPay.QR do
  def generate(client, body), do: MonaPay.generate_qr(client, body)
  def cancel(client, qr_code_id, body \\ nil), do: MonaPay.cancel_qr(client, qr_code_id, body)
end

defmodule MonaPay.Transactions do
  def list(client, virtual_account_number, options \\ []),
    do: MonaPay.list_transactions(client, virtual_account_number, options)

  def stream(client, virtual_account_number, options \\ []),
    do: MonaPay.stream_transactions(client, virtual_account_number, options)

  def retry(client, transaction_id, target_type, target_id \\ nil),
    do: MonaPay.retry_transaction(client, transaction_id, target_type, target_id)
end

defmodule MonaPay.Webhooks do
  def list(client), do: MonaPay.list_webhooks(client)
  def create(client, body), do: MonaPay.create_webhook(client, body)
  def update(client, config_id, body), do: MonaPay.update_webhook(client, config_id, body)
  def remove(client, config_id), do: MonaPay.remove_webhook(client, config_id)
  def test(client, body \\ %{"is_dummy" => true}), do: MonaPay.test_webhook(client, body)
end

defmodule MonaPay.WebhookLogs do
  def list(client, options \\ []), do: MonaPay.list_webhook_logs(client, options)
  def stats(client, options \\ []), do: MonaPay.webhook_log_stats(client, options)
end

defmodule MonaPay.Sandbox do
  def create_transaction(client, body), do: MonaPay.create_sandbox_transaction(client, body)
end

defmodule MonaPay.EmailConfigs do
  def list(client), do: MonaPay.list_email_configs(client)
  def create(client, body), do: MonaPay.create_email_config(client, body)
  def get(client, id), do: MonaPay.get_email_config(client, id)
  def update(client, id, body), do: MonaPay.update_email_config(client, id, body)
  def remove(client, id), do: MonaPay.remove_email_config(client, id)
  def verify(client, id, email, code), do: MonaPay.verify_email_config(client, id, email, code)
  def resend_verification(client, id, email), do: MonaPay.resend_email_verification(client, id, email)
  def test(client, id), do: MonaPay.test_email_config(client, id)
end

defmodule MonaPay.EmailLogs do
  def list(client, options \\ []), do: MonaPay.list_email_logs(client, options)
  def stats(client, options \\ []), do: MonaPay.email_log_stats(client, options)
end

defmodule MonaPay.EmailSuppressions do
  def list(client), do: MonaPay.list_email_suppressions(client)
  def remove(client, email), do: MonaPay.remove_email_suppression(client, email)
end
