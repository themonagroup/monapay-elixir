defmodule MonaPay.Keys do
  def generate(client, name \\ "Default Key"), do: MonaPay.generate_key(client, name)
  def list(client), do: MonaPay.list_keys(client)
  def destroy(client, key_id), do: MonaPay.destroy_key(client, key_id)
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
