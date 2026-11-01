defmodule Refract.DB.FromSchema do
  @moduledoc false

  import Refract.DB.ArgValidator, only: [validate_schema!: 1]

  alias Refract.Parse
  alias Refract.Table

  @datetimes [:naive_datetime, :naive_datetime_usec, :utc_datetime, :utc_datetime_usec]

  @type opt ::
          {:name, String.t()}
          | {:version, pos_integer()}
          | {:required, [atom()]}
          | {:aliases, %{atom() => [String.t() | Regex.t()]}}
          | {:except, [atom()]}

  @spec run(module(), [opt()]) :: Refract.Shape.t()

  def run(schema, opts) do
    validate_schema!(schema)

    opts =
      Keyword.validate!(opts,
        name: schema.__schema__(:source),
        version: 1,
        required: [],
        aliases: %{},
        except: generated(schema)
      )

    required = Keyword.fetch!(opts, :required)
    aliases = Keyword.fetch!(opts, :aliases)
    except = Keyword.fetch!(opts, :except)

    validate_fields(required, schema, :required)
    validate_aliases(aliases, schema)
    validate_fields(except, schema, :except)

    fields = schema.__schema__(:fields) -- except
    rules = Map.new(fields, &{&1, rule(schema.__schema__(:type, &1), schema, &1)})

    Refract.Shape.new(
      name: Keyword.fetch!(opts, :name),
      version: Keyword.fetch!(opts, :version),
      spec:
        Table.spec(
          header: [
            columns: Map.new(fields, &{column(schema, &1), names(schema, &1, aliases)}),
            required: Enum.map(required, &column(schema, &1)),
            min_matches: max(length(required), 1)
          ],
          row: [match: row_rules(required, rules, schema)]
        ),
      validation: [columns: validation_rules(fields, required, rules, schema)]
    )
  end

  defp generated(schema) do
    schema.__schema__(:autogenerate)
    |> Enum.flat_map(&elem(&1, 0))
    |> generated_id(schema.__schema__(:autogenerate_id))
  end

  defp generated_id(fields, nil), do: fields
  defp generated_id(fields, {key, _source, _type}), do: [key | fields]

  defp column(schema, field), do: Atom.to_string(schema.__schema__(:field_source, field))

  defp names(schema, field, aliases),
    do: Enum.uniq([column(schema, field), Atom.to_string(field) | Map.get(aliases, field, [])])

  defp row_rules(required, rules, schema) do
    for field <- required, rule = row_rule(Map.fetch!(rules, field)), into: %{} do
      {column(schema, field), rule}
    end
  end

  defp row_rule({:in, _values}), do: nil
  defp row_rule(rule), do: rule

  defp validation_rules(fields, required, rules, schema) do
    for field <- fields,
        column_rules = column_rules(field in required, Map.fetch!(rules, field)),
        column_rules != [],
        into: %{},
        do: {column(schema, field), column_rules}
  end

  defp column_rules(true, rule), do: [:required | column_rules(false, rule)]
  defp column_rules(false, nil), do: []
  defp column_rules(false, rule), do: [rule]

  defp rule(type, _schema, _field) when type in [:id, :integer], do: :integer
  defp rule(type, _schema, _field) when type in [:float, :decimal], do: :number
  defp rule(:date, _schema, _field), do: :date
  defp rule(type, _schema, _field) when type in @datetimes, do: :datetime
  defp rule(:boolean, _schema, _field), do: {:boolean, &boolean?/1}
  defp rule(type, _schema, _field) when type in [:binary_id, Ecto.UUID], do: uuid()

  defp rule({:parameterized, {Ecto.Enum, _params}}, schema, field),
    do: {:in, Ecto.Enum.dump_values(schema, field)}

  defp rule(_type, _schema, _field), do: nil

  defp boolean?(cell), do: match?({:ok, _boolean}, Parse.boolean(cell))

  defp uuid, do: ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

  defp validate_fields(fields, schema, name) when is_list(fields),
    do: Enum.each(fields, &validate_field(&1, schema, name))

  defp validate_fields(fields, _schema, name) do
    raise ArgumentError, "#{name} must be a list of field names, got: #{inspect(fields)}"
  end

  defp validate_aliases(aliases, schema) when is_map(aliases) do
    Enum.each(aliases, fn {field, names} ->
      validate_field(field, schema, :aliases)
      validate_names(names, field)
    end)
  end

  defp validate_aliases(aliases, _schema) do
    raise ArgumentError, "aliases must be a map of field to names, got: #{inspect(aliases)}"
  end

  defp validate_names(names, _field) when is_list(names), do: :ok

  defp validate_names(names, field) do
    raise ArgumentError, "aliases for #{field} must be a list, got: #{inspect(names)}"
  end

  defp validate_field(field, schema, name) do
    if field not in schema.__schema__(:fields) do
      raise ArgumentError, "#{name}: #{inspect(field)} is not a field of #{inspect(schema)}"
    end
  end
end
