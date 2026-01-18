defmodule Cart.ShoppingCart do
  @moduledoc "Shopping cart with item management, pricing, discounts, taxes, and shipping.\n"
  alias Cart.Product
  defstruct items: %{}, coupon: nil, shipping_address: nil, tax_rate: Decimal.new("0.08")
  @type item :: %{product: Product.t(), quantity: non_neg_integer()}
  @type t :: %__MODULE__{
          items: %{String.t() => item()},
          coupon: String.t() | nil,
          shipping_address: map() | nil,
          tax_rate: Decimal.t()
        }
  @doc "Creates a new empty cart"
  def new(opts \\ []) do
    tax_rate = Keyword.get(opts, :tax_rate, Decimal.new("0.08"))
    %__MODULE__{tax_rate: tax_rate}
  end

  @doc "Adds a product to the cart"
  def add_item(%__MODULE__{items: items} = cart, %Product{} = product, quantity)
      when quantity > 0 do
    if Product.available?(product, quantity) do
      items =
        Map.update(
          items,
          product.id,
          %{product: product, quantity: quantity},
          fn existing ->
            new_quantity = existing.quantity + quantity

            if Product.available?(product, new_quantity) do
              %{existing | quantity: new_quantity}
            else
              existing
            end
          end
        )

      {:ok, %{cart | items: items}}
    else
      {:error, :insufficient_stock}
    end
  end

  def add_item(_cart, _product, _quantity) do
    {:error, :invalid_quantity}
  end

  @doc "Removes a product from the cart"
  def remove_item(%__MODULE__{items: items} = cart, product_id) do
    if Map.has_key?(items, product_id) do
      {:ok, %{cart | items: Map.delete(items, product_id)}}
    else
      {:error, :item_not_found}
    end
  end

  @doc "Updates quantity of a product in the cart"
  def update_quantity(%__MODULE__{items: items} = cart, product_id, new_quantity)
      when new_quantity > 0 do
    case Map.fetch(items, product_id) do
      {:ok, %{product: product}} ->
        if Product.available?(product, new_quantity) do
          items = Map.update!(items, product_id, &%{&1 | quantity: new_quantity})
          {:ok, %{cart | items: items}}
        else
          {:error, :insufficient_stock}
        end

      :error ->
        {:error, :item_not_found}
    end
  end

  def update_quantity(%__MODULE__{} = cart, product_id, 0) do
    remove_item(cart, product_id)
  end

  def update_quantity(_cart, _product_id, _quantity) do
    {:error, :invalid_quantity}
  end

  @doc "Clears all items from the cart"
  def clear(%__MODULE__{} = cart) do
    %{cart | items: %{}}
  end

  @doc "Returns the total number of items in the cart"
  def item_count(%__MODULE__{items: items}) do
    Enum.reduce(items, 0, fn {_id, %{quantity: qty}}, acc -> acc + qty end)
  end

  @doc "Checks if the cart is empty"
  def empty?(%__MODULE__{items: items}) do
    map_size(items) == 0
  end

  @doc "Calculates subtotal before discounts and taxes"
  def subtotal(%__MODULE__{items: items}) do
    Enum.reduce(items, Decimal.new(0), fn {_id, %{product: product, quantity: qty}}, acc ->
      item_price = Product.calculate_price(product, qty)
      Decimal.add(acc, item_price)
    end)
  end

  @doc "Applies a coupon code and returns discount amount"
  def apply_coupon(%__MODULE__{} = cart, coupon_code) when is_binary(coupon_code) do
    case validate_coupon(coupon_code, cart) do
      {:ok, discount} -> {:ok, %{cart | coupon: coupon_code}, discount}
      {:error, _} = error -> error
    end
  end

  @doc "Removes the applied coupon"
  def remove_coupon(%__MODULE__{} = cart) do
    %{cart | coupon: nil}
  end

  @doc "Calculates coupon discount"
  def coupon_discount(%__MODULE__{coupon: nil}) do
    Decimal.new(0)
  end

  def coupon_discount(%__MODULE__{coupon: coupon} = cart) do
    subtotal = subtotal(cart)

    discount_rate =
      case coupon do
        "SAVE10" -> Decimal.new("0.10")
        "SAVE20" -> Decimal.new("0.20")
        "SAVE50" -> Decimal.new("0.50")
        "FREESHIP" -> Decimal.new(0)
        _ -> Decimal.new(0)
      end

    discount = Decimal.mult(subtotal, discount_rate)
    max_discount = Decimal.new(100)

    if Decimal.compare(discount, max_discount) == :gt do
      max_discount
    else
      discount
    end
  end

  @doc "Sets the shipping address"
  def set_shipping_address(%__MODULE__{} = cart, address) when is_map(address) do
    with :ok <- validate_address(address) do
      {:ok, %{cart | shipping_address: address}}
    end
  end

  @doc "Calculates shipping cost based on weight and address"
  def shipping_cost(%__MODULE__{items: items, shipping_address: address, coupon: coupon}) do
    if address == nil do
      Decimal.new(0)
    else
      total_weight =
        Enum.reduce(items, 0.0, fn {_id, %{product: product, quantity: qty}}, acc ->
          acc + Product.shipping_weight(product, qty)
        end)

      base_rate =
        cond do
          total_weight >= 50.0 -> Decimal.new("25.00")
          total_weight >= 20.0 -> Decimal.new("15.00")
          total_weight >= 10.0 -> Decimal.new("10.00")
          total_weight >= 5.0 -> Decimal.new("7.50")
          true -> Decimal.new("5.00")
        end

      zone_multiplier =
        case Map.get(address, :country) do
          "US" -> Decimal.new("1.0")
          "CA" -> Decimal.new("1.5")
          "MX" -> Decimal.new("1.3")
          _ -> Decimal.new("2.0")
        end

      shipping = Decimal.mult(base_rate, zone_multiplier)

      if coupon == "FREESHIP" do
        Decimal.new(0)
      else
        shipping
      end
    end
  end

  @doc "Calculates tax on subtotal minus coupon discount"
  def tax(%__MODULE__{items: items, tax_rate: tax_rate} = cart) do
    taxable_items = Enum.filter(items, fn {_id, %{product: product}} -> product.taxable end)

    taxable_subtotal =
      Enum.reduce(taxable_items, Decimal.new(0), fn {_id, %{product: product, quantity: qty}},
                                                    acc ->
        item_price = Product.calculate_price(product, qty)
        Decimal.add(acc, item_price)
      end)

    discount = coupon_discount(cart)
    discount_ratio = Decimal.div(discount, subtotal(cart))
    taxable_discount = Decimal.mult(taxable_subtotal, discount_ratio)
    taxable_amount = Decimal.sub(taxable_subtotal, taxable_discount)
    Decimal.mult(taxable_amount, tax_rate)
  end

  @doc "Calculates the total amount to charge"
  def total(%__MODULE__{} = cart) do
    subtotal = subtotal(cart)
    discount = coupon_discount(cart)
    shipping = shipping_cost(cart)
    tax = tax(cart)
    subtotal |> Decimal.sub(discount) |> Decimal.add(shipping) |> Decimal.add(tax)
  end

  @doc "Gets a summary of the cart"
  def summary(%__MODULE__{} = cart) do
    %{
      item_count: item_count(cart),
      subtotal: subtotal(cart),
      coupon_discount: coupon_discount(cart),
      shipping: shipping_cost(cart),
      tax: tax(cart),
      total: total(cart)
    }
  end

  @doc "Validates if cart can be checked out"
  def can_checkout?(%__MODULE__{items: items, shipping_address: address}) do
    not empty?(%__MODULE__{items: items}) and address != nil
  end

  defp validate_coupon(coupon_code, cart) do
    min_subtotal =
      case coupon_code do
        "SAVE10" -> Decimal.new(20)
        "SAVE20" -> Decimal.new(50)
        "SAVE50" -> Decimal.new(100)
        "FREESHIP" -> Decimal.new(0)
        _ -> {:error, :invalid_coupon}
      end

    case min_subtotal do
      {:error, _} = error ->
        error

      min ->
        current_subtotal = subtotal(cart)

        if Decimal.compare(current_subtotal, min) != :lt do
          discount_rate =
            case coupon_code do
              "SAVE10" -> Decimal.new("0.10")
              "SAVE20" -> Decimal.new("0.20")
              "SAVE50" -> Decimal.new("0.50")
              "FREESHIP" -> Decimal.new(0)
            end

          discount = Decimal.mult(current_subtotal, discount_rate)
          {:ok, discount}
        else
          {:error, :minimum_not_met}
        end
    end
  end

  defp validate_address(address) do
    required = [:street, :city, :country, :postal_code]

    if Enum.all?(required, &Map.has_key?(address, &1)) do
      :ok
    else
      {:error, :invalid_address}
    end
  end
end