defmodule Cart.Product do
  @moduledoc """
  Product management with pricing, inventory, and validation.
  """

  defstruct [:id, :name, :price, :stock, :category, :weight, :taxable]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          price: Decimal.t(),
          stock: non_neg_integer(),
          category: atom(),
          weight: float(),
          taxable: boolean()
        }

  @doc "Creates a new product with validation"
  def new(attrs) do
    with :ok <- validate_attrs(attrs),
         product <- struct(__MODULE__, attrs),
         :ok <- validate_product(product) do
      {:ok, product}
    end
  end

  @doc "Checks if product is available in requested quantity"
  def available?(%__MODULE__{stock: stock}, quantity) when quantity > 0 do
    stock >= quantity
  end

  def available?(_product, _quantity), do: false

  @doc "Calculates total price for quantity with bulk discount"
  def calculate_price(%__MODULE__{price: price}, quantity) when quantity > 0 do
    base_price = Decimal.mult(price, Decimal.new(quantity))

    discount_rate =
      cond do
        quantity >= 100 -> Decimal.new("0.20")
        quantity >= 50 -> Decimal.new("0.15")
        quantity >= 10 -> Decimal.new("0.10")
        quantity >= 5 -> Decimal.new("0.05")
        true -> Decimal.new("0")
      end

    discount = Decimal.mult(base_price, discount_rate)
    Decimal.sub(base_price, discount)
  end

  @doc "Reduces stock by quantity"
  def reduce_stock(%__MODULE__{stock: stock} = product, quantity)
      when quantity > 0 and stock >= quantity do
    {:ok, %{product | stock: stock - quantity}}
  end

  def reduce_stock(_product, _quantity), do: {:error, :insufficient_stock}

  @doc "Restores stock by quantity"
  def restore_stock(%__MODULE__{stock: stock} = product, quantity) when quantity > 0 do
    {:ok, %{product | stock: stock + quantity}}
  end

  def restore_stock(_product, _quantity), do: {:error, :invalid_quantity}

  @doc "Checks if product needs restock"
  def needs_restock?(%__MODULE__{stock: stock, category: category}) do
    threshold =
      case category do
        :electronics -> 10
        :clothing -> 20
        :food -> 50
        :books -> 15
        _ -> 5
      end

    stock < threshold
  end

  @doc "Calculates shipping weight for quantity"
  def shipping_weight(%__MODULE__{weight: weight}, quantity) when quantity > 0 do
    weight * quantity
  end

  @doc "Applies seasonal discount"
  def seasonal_discount(%__MODULE__{price: price, category: category}, season) do
    discount_rate =
      case {category, season} do
        {:clothing, :winter} -> Decimal.new("0.30")
        {:clothing, :summer} -> Decimal.new("0.25")
        {:electronics, :black_friday} -> Decimal.new("0.40")
        {:books, :back_to_school} -> Decimal.new("0.20")
        {_, :clearance} -> Decimal.new("0.50")
        _ -> Decimal.new("0")
      end

    discount = Decimal.mult(price, discount_rate)
    discounted_price = Decimal.sub(price, discount)

    if Decimal.compare(discounted_price, Decimal.new("0.01")) == :lt do
      Decimal.new("0.01")
    else
      discounted_price
    end
  end

  # Private validation functions

  defp validate_attrs(attrs) do
    required = [:id, :name, :price, :stock, :category, :weight, :taxable]

    if Enum.all?(required, &Map.has_key?(attrs, &1)) do
      :ok
    else
      {:error, :missing_required_fields}
    end
  end

  defp validate_product(%__MODULE__{} = product) do
    with :ok <- validate_price(product.price),
         :ok <- validate_stock(product.stock),
         :ok <- validate_weight(product.weight),
         :ok <- validate_name(product.name) do
      :ok
    end
  end

  defp validate_price(price) do
    if Decimal.compare(price, Decimal.new(0)) == :gt do
      :ok
    else
      {:error, :invalid_price}
    end
  end

  defp validate_stock(stock) when is_integer(stock) and stock >= 0, do: :ok
  defp validate_stock(_), do: {:error, :invalid_stock}

  defp validate_weight(weight) when is_float(weight) and weight > 0.0, do: :ok
  defp validate_weight(_), do: {:error, :invalid_weight}

  defp validate_name(name) when is_binary(name) do
    if String.length(name) > 0 and String.length(name) <= 200 do
      :ok
    else
      {:error, :invalid_name}
    end
  end

  defp validate_name(_), do: {:error, :invalid_name}
end
