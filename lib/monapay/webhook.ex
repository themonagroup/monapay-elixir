defmodule MonaPay.Webhook do
  @moduledoc "Xác minh chữ ký webhook MONA Pay trên raw request body."

  import Bitwise

  def verify_webhook(raw, timestamp, signature, secret, tolerance \\ 300)

  def verify_webhook(_raw, _timestamp, _signature, _secret, tolerance)
      when not is_integer(tolerance) or tolerance < 0 do
    raise ArgumentError, "tolerance phải là số nguyên không âm"
  end

  def verify_webhook(raw, timestamp, signature, secret, tolerance) when is_binary(raw) do
    timestamp = to_string(timestamp || "")
    signature = to_string(signature || "")

    cond do
      timestamp == "" ->
        invalid(:missing_timestamp)

      not Regex.match?(~r/\A\d+\z/, timestamp) ->
        invalid(:invalid_timestamp)

      abs(System.system_time(:second) - String.to_integer(timestamp)) > tolerance ->
        invalid(:timestamp_out_of_tolerance)

      signature == "" ->
        invalid(:missing_signature)

      true ->
        expected = :crypto.mac(:hmac, :sha256, to_string(secret), timestamp <> "." <> raw)
        valid_format = Regex.match?(~r/\Asha256=[0-9a-fA-F]{64}\z/, signature)

        supplied =
          if valid_format do
            case Base.decode16(binary_part(signature, 7, 64), case: :mixed) do
              {:ok, digest} -> digest
              :error -> :binary.copy(<<0>>, 32)
            end
          else
            :binary.copy(<<0>>, 32)
          end

        if secure_compare(expected, supplied) and valid_format do
          case MonaPay.JSON.decode(raw) do
            {:ok, payload} -> %{ok: true, payload: payload}
            {:error, _reason} -> invalid(:invalid_json)
          end
        else
          invalid(:invalid_signature)
        end
    end
  end

  defp invalid(reason), do: %{ok: false, reason: reason}

  defp secure_compare(left, right) when byte_size(left) == byte_size(right),
    do: compare(left, right, 0) == 0

  defp secure_compare(_left, _right), do: false
  defp compare(<<>>, <<>>, difference), do: difference

  defp compare(<<left, left_rest::binary>>, <<right, right_rest::binary>>, difference),
    do: compare(left_rest, right_rest, difference ||| bxor(left, right))
end
