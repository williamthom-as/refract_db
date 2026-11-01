defmodule Refract.DB.Cells do
  @moduledoc false

  alias Refract.DB.Source

  @spec lines(Source.t(), [String.t()], [[term()]]) :: [Refract.raw_row()]

  def lines(%Source{fields: fields} = source, columns, rows) do
    picks = Enum.map(columns, &Map.get(fields, &1))

    Enum.map(rows, &line(source, columns, picks, &1))
  end

  defp line(%Source{schema: nil}, _columns, _picks, row), do: Enum.map(row, &cell/1)

  defp line(%Source{repo: repo, schema: schema}, columns, picks, row) do
    loaded = repo.load(schema, {columns, row})

    Enum.zip_with(picks, row, &(loaded |> value(&1, &2) |> cell()))
  end

  defp value(_loaded, nil, raw), do: raw
  defp value(loaded, field, _raw), do: Map.fetch!(loaded, field)

  defp cell(nil), do: nil
  defp cell(value) when is_boolean(value) or is_number(value), do: value
  defp cell(value) when is_atom(value), do: Atom.to_string(value)
  defp cell(value) when is_binary(value), do: text(value, String.valid?(value))
  defp cell(%Decimal{} = value), do: value
  defp cell(%Date{} = value), do: value
  defp cell(%Time{} = value), do: value
  defp cell(%NaiveDateTime{} = value), do: value
  defp cell(%DateTime{} = value), do: value
  defp cell(%Duration{} = value), do: Duration.to_iso8601(value)
  defp cell(%_struct{} = value), do: value |> String.Chars.impl_for() |> struct_text(value)
  defp cell(value) when is_map(value) or is_list(value), do: JSON.encode!(value)

  defp struct_text(nil, value), do: inspect(value)
  defp struct_text(_impl, value), do: to_string(value)

  defp text(value, true), do: value
  defp text(value, false), do: Base.encode16(value, case: :lower)
end
