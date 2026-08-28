defmodule MonaPay.JSON do
  @moduledoc false

  def encode(value), do: encode_value(value)

  def decode(value) when is_binary(value) do
    with {:ok, decoded, rest} <- parse_value(skip_whitespace(value)),
         "" <- skip_whitespace(rest) do
      {:ok, decoded}
    else
      {:error, _reason} = error -> error
      _rest -> {:error, "JSON có dữ liệu thừa"}
    end
  end

  defp encode_value(nil), do: "null"
  defp encode_value(true), do: "true"
  defp encode_value(false), do: "false"
  defp encode_value(value) when is_integer(value), do: Integer.to_string(value)
  defp encode_value(value) when is_float(value), do: :erlang.float_to_binary(value, [:compact])
  defp encode_value(value) when is_binary(value), do: [?\", escape(value), ?\"]

  defp encode_value(value) when is_list(value) do
    [?[, Enum.intersperse(Enum.map(value, &encode_value/1), ?,), ?]]
  end

  defp encode_value(value) when is_map(value) do
    entries = Enum.map(value, fn {key, item} -> [encode_value(key_to_string(key)), ?:, encode_value(item)] end)
    [?{, Enum.intersperse(entries, ?,), ?}]
  end

  defp encode_value(value), do: raise(ArgumentError, "không encode được JSON value: #{inspect(value)}")

  defp key_to_string(key) when is_binary(key), do: key
  defp key_to_string(key) when is_atom(key), do: Atom.to_string(key)
  defp key_to_string(key), do: to_string(key)

  defp escape(value), do: escape(value, []) |> Enum.reverse()
  defp escape(<<>>, output), do: output
  defp escape(<<?\", rest::binary>>, output), do: escape(rest, ["\\\"" | output])
  defp escape(<<?\\, rest::binary>>, output), do: escape(rest, ["\\\\" | output])
  defp escape(<<?\b, rest::binary>>, output), do: escape(rest, ["\\b" | output])
  defp escape(<<?\f, rest::binary>>, output), do: escape(rest, ["\\f" | output])
  defp escape(<<?\n, rest::binary>>, output), do: escape(rest, ["\\n" | output])
  defp escape(<<?\r, rest::binary>>, output), do: escape(rest, ["\\r" | output])
  defp escape(<<?\t, rest::binary>>, output), do: escape(rest, ["\\t" | output])

  defp escape(<<character::utf8, rest::binary>>, output) when character < 0x20 do
    escape(rest, ["\\u" <> hex4(character) | output])
  end

  defp escape(<<character::utf8, rest::binary>>, output),
    do: escape(rest, [<<character::utf8>> | output])

  defp hex4(value), do: value |> Integer.to_string(16) |> String.pad_leading(4, "0")

  defp parse_value(<<"null", rest::binary>>), do: {:ok, nil, rest}
  defp parse_value(<<"true", rest::binary>>), do: {:ok, true, rest}
  defp parse_value(<<"false", rest::binary>>), do: {:ok, false, rest}
  defp parse_value(<<?\", rest::binary>>), do: parse_string(rest, [])
  defp parse_value(<<?[, rest::binary>>), do: parse_array(skip_whitespace(rest), [])
  defp parse_value(<<?{, rest::binary>>), do: parse_object(skip_whitespace(rest), %{})

  defp parse_value(value) do
    case Regex.run(~r/\A-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?/, value) do
      [number] ->
        rest = binary_part(value, byte_size(number), byte_size(value) - byte_size(number))
        {:ok, parse_number(number), rest}

      _ ->
        {:error, "JSON value không hợp lệ"}
    end
  end

  defp parse_number(value) do
    if String.contains?(value, [".", "e", "E"]) do
      {number, ""} = Float.parse(value)
      number
    else
      {number, ""} = Integer.parse(value)
      number
    end
  end

  defp parse_string(<<?\", rest::binary>>, output),
    do: {:ok, output |> Enum.reverse() |> IO.iodata_to_binary(), rest}

  defp parse_string(<<?\\, escape, rest::binary>>, output) do
    case escape do
      ?\" -> parse_string(rest, [?\" | output])
      ?\\ -> parse_string(rest, [?\\ | output])
      ?/ -> parse_string(rest, [?/ | output])
      ?b -> parse_string(rest, [?\b | output])
      ?f -> parse_string(rest, [?\f | output])
      ?n -> parse_string(rest, [?\n | output])
      ?r -> parse_string(rest, [?\r | output])
      ?t -> parse_string(rest, [?\t | output])
      ?u -> parse_unicode(rest, output)
      _ -> {:error, "JSON escape không hợp lệ"}
    end
  end

  defp parse_string(<<character::utf8, _rest::binary>>, _output) when character < 0x20,
    do: {:error, "JSON string có control character"}

  defp parse_string(<<character::utf8, rest::binary>>, output),
    do: parse_string(rest, [<<character::utf8>> | output])

  defp parse_string(<<>>, _output), do: {:error, "JSON string chưa đóng"}
  defp parse_string(_invalid_utf8, _output), do: {:error, "JSON string không phải UTF-8"}

  defp parse_unicode(<<hex::binary-size(4), rest::binary>>, output) do
    with {high, ""} <- Integer.parse(hex, 16),
         {:ok, codepoint, tail} <- surrogate(high, rest),
         true <- codepoint <= 0x10FFFF do
      parse_string(tail, [<<codepoint::utf8>> | output])
    else
      _ -> {:error, "JSON unicode escape không hợp lệ"}
    end
  end

  defp parse_unicode(_, _output), do: {:error, "JSON unicode escape bị cắt"}

  defp surrogate(high, <<?\\, ?u, low_hex::binary-size(4), rest::binary>>) when high in 0xD800..0xDBFF do
    case Integer.parse(low_hex, 16) do
      {low, ""} when low in 0xDC00..0xDFFF ->
        {:ok, 0x10000 + (high - 0xD800) * 1024 + low - 0xDC00, rest}

      _ ->
        {:error, :invalid_surrogate}
    end
  end

  defp surrogate(high, _rest) when high in 0xD800..0xDFFF, do: {:error, :invalid_surrogate}
  defp surrogate(high, rest), do: {:ok, high, rest}

  defp parse_array(<<?], rest::binary>>, output), do: {:ok, Enum.reverse(output), rest}

  defp parse_array(value, output) do
    with {:ok, item, rest} <- parse_value(value) do
      case skip_whitespace(rest) do
        <<?,, tail::binary>> -> parse_array(skip_whitespace(tail), [item | output])
        <<?], tail::binary>> -> {:ok, Enum.reverse([item | output]), tail}
        _ -> {:error, "JSON array không hợp lệ"}
      end
    end
  end

  defp parse_object(<<?}, rest::binary>>, output), do: {:ok, output, rest}

  defp parse_object(<<?\", rest::binary>>, output) do
    with {:ok, key, after_key} <- parse_string(rest, []),
         <<?:, after_colon::binary>> <- skip_whitespace(after_key),
         {:ok, value, after_value} <- parse_value(skip_whitespace(after_colon)) do
      case skip_whitespace(after_value) do
        <<?,, tail::binary>> -> parse_object(skip_whitespace(tail), Map.put(output, key, value))
        <<?}, tail::binary>> -> {:ok, Map.put(output, key, value), tail}
        _ -> {:error, "JSON object không hợp lệ"}
      end
    else
      {:error, _reason} = error -> error
      _ -> {:error, "JSON object không hợp lệ"}
    end
  end

  defp parse_object(_, _output), do: {:error, "JSON object key phải là string"}

  defp skip_whitespace(<<?\s, rest::binary>>), do: skip_whitespace(rest)
  defp skip_whitespace(<<?\n, rest::binary>>), do: skip_whitespace(rest)
  defp skip_whitespace(<<?\r, rest::binary>>), do: skip_whitespace(rest)
  defp skip_whitespace(<<?\t, rest::binary>>), do: skip_whitespace(rest)
  defp skip_whitespace(rest), do: rest
end
