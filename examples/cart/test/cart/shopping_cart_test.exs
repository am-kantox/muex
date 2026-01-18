defmodule Cart.ShoppingCartTest do
  use ExUnit.Case, async: true

  alias Cart.{Product, ShoppingCart}

  defp create_product(id, price, stock, opts \\ []) do
    {:ok, product} =
      Product.new(%{
        id: id,
        name: Keyword.get(opts, :name, "Product #{id}"),
        price: Decimal.new(price),
        stock: stock,
        category: Keyword.get(opts, :category, :electronics),
        weight: Keyword.get(opts, :weight, 1.0),
        taxable: Keyword.get(opts, :taxable, true)
      })

    product
  end

  describe "new/1" do
    test "creates an empty cart with default tax rate" do
      cart = ShoppingCart.new()
      assert ShoppingCart.empty?(cart)
      assert Decimal.equal?(cart.tax_rate, Decimal.new("0.08"))
    end

    test "creates cart with custom tax rate" do
      cart = ShoppingCart.new(tax_rate: Decimal.new("0.10"))
      assert Decimal.equal?(cart.tax_rate, Decimal.new("0.10"))
    end
  end

  describe "add_item/3" do
    test "adds a product to empty cart" do
      cart = ShoppingCart.new()
      product = create_product("prod-1", "100.00", 10)

      assert {:ok, cart} = ShoppingCart.add_item(cart, product, 2)
      assert ShoppingCart.item_count(cart) == 2
      refute ShoppingCart.empty?(cart)
    end

    test "increases quantity when adding same product twice" do
      cart = ShoppingCart.new()
      product = create_product("prod-1", "100.00", 10)

      {:ok, cart} = ShoppingCart.add_item(cart, product, 2)
      {:ok, cart} = ShoppingCart.add_item(cart, product, 3)

      assert ShoppingCart.item_count(cart) == 5
    end

    test "returns error when insufficient stock" do
      cart = ShoppingCart.new()
      product = create_product("prod-1", "100.00", 5)

      assert {:error, :insufficient_stock} = ShoppingCart.add_item(cart, product, 10)
    end

    test "returns error for zero quantity" do
      cart = ShoppingCart.new()
      product = create_product("prod-1", "100.00", 10)

      assert {:error, :invalid_quantity} = ShoppingCart.add_item(cart, product, 0)
    end

    test "returns error for negative quantity" do
      cart = ShoppingCart.new()
      product = create_product("prod-1", "100.00", 10)

      assert {:error, :invalid_quantity} = ShoppingCart.add_item(cart, product, -1)
    end

    test "returns error when trying to add beyond stock" do
      cart = ShoppingCart.new()
      product = create_product("prod-1", "100.00", 5)

      {:ok, cart} = ShoppingCart.add_item(cart, product, 3)
      # Trying to add 10 more would exceed stock of 5
      assert {:error, :insufficient_stock} = ShoppingCart.add_item(cart, product, 10)
      # Original quantity remains
      assert ShoppingCart.item_count(cart) == 3
    end
  end

  describe "remove_item/2" do
    test "removes a product from cart" do
      cart = ShoppingCart.new()
      product = create_product("prod-1", "100.00", 10)

      {:ok, cart} = ShoppingCart.add_item(cart, product, 2)
      {:ok, cart} = ShoppingCart.remove_item(cart, "prod-1")

      assert ShoppingCart.empty?(cart)
    end

    test "returns error for non-existent product" do
      cart = ShoppingCart.new()

      assert {:error, :item_not_found} = ShoppingCart.remove_item(cart, "nonexistent")
    end
  end

  describe "update_quantity/3" do
    test "updates quantity of existing product" do
      cart = ShoppingCart.new()
      product = create_product("prod-1", "100.00", 10)

      {:ok, cart} = ShoppingCart.add_item(cart, product, 2)
      {:ok, cart} = ShoppingCart.update_quantity(cart, "prod-1", 5)

      assert ShoppingCart.item_count(cart) == 5
    end

    test "removes item when updating to zero" do
      cart = ShoppingCart.new()
      product = create_product("prod-1", "100.00", 10)

      {:ok, cart} = ShoppingCart.add_item(cart, product, 2)
      {:ok, cart} = ShoppingCart.update_quantity(cart, "prod-1", 0)

      assert ShoppingCart.empty?(cart)
    end

    test "returns error when insufficient stock" do
      cart = ShoppingCart.new()
      product = create_product("prod-1", "100.00", 5)

      {:ok, cart} = ShoppingCart.add_item(cart, product, 2)

      assert {:error, :insufficient_stock} = ShoppingCart.update_quantity(cart, "prod-1", 10)
    end

    test "returns error for non-existent product" do
      cart = ShoppingCart.new()

      assert {:error, :item_not_found} = ShoppingCart.update_quantity(cart, "nonexistent", 5)
    end

    test "returns error for negative quantity" do
      cart = ShoppingCart.new()
      product = create_product("prod-1", "100.00", 10)

      {:ok, cart} = ShoppingCart.add_item(cart, product, 2)

      assert {:error, :invalid_quantity} = ShoppingCart.update_quantity(cart, "prod-1", -1)
    end
  end

  describe "clear/1" do
    test "removes all items from cart" do
      cart = ShoppingCart.new()
      product1 = create_product("prod-1", "100.00", 10)
      product2 = create_product("prod-2", "50.00", 10)

      {:ok, cart} = ShoppingCart.add_item(cart, product1, 2)
      {:ok, cart} = ShoppingCart.add_item(cart, product2, 3)

      cart = ShoppingCart.clear(cart)

      assert ShoppingCart.empty?(cart)
    end
  end

  describe "subtotal/1" do
    test "calculates subtotal for single product" do
      cart = ShoppingCart.new()
      product = create_product("prod-1", "100.00", 10)

      {:ok, cart} = ShoppingCart.add_item(cart, product, 2)

      assert Decimal.equal?(ShoppingCart.subtotal(cart), Decimal.new("200.00"))
    end

    test "calculates subtotal for multiple products" do
      cart = ShoppingCart.new()
      product1 = create_product("prod-1", "100.00", 10)
      product2 = create_product("prod-2", "50.00", 10)

      {:ok, cart} = ShoppingCart.add_item(cart, product1, 2)
      {:ok, cart} = ShoppingCart.add_item(cart, product2, 3)

      assert Decimal.equal?(ShoppingCart.subtotal(cart), Decimal.new("350.00"))
    end

    test "applies bulk discount in subtotal" do
      cart = ShoppingCart.new()
      product = create_product("prod-1", "100.00", 50)

      {:ok, cart} = ShoppingCart.add_item(cart, product, 10)

      expected = Decimal.mult(Decimal.new("1000.00"), Decimal.new("0.90"))
      assert Decimal.equal?(ShoppingCart.subtotal(cart), expected)
    end

    test "returns zero for empty cart" do
      cart = ShoppingCart.new()

      assert Decimal.equal?(ShoppingCart.subtotal(cart), Decimal.new("0"))
    end
  end

  describe "apply_coupon/2" do
    setup do
      cart = ShoppingCart.new()
      product = create_product("prod-1", "100.00", 100)
      {:ok, cart} = ShoppingCart.add_item(cart, product, 3)
      %{cart: cart}
    end

    test "applies valid SAVE10 coupon", %{cart: cart} do
      assert {:ok, updated_cart, discount} = ShoppingCart.apply_coupon(cart, "SAVE10")
      assert updated_cart.coupon == "SAVE10"
      assert Decimal.equal?(discount, Decimal.new("30.00"))
    end

    test "applies valid SAVE20 coupon", %{cart: cart} do
      assert {:ok, updated_cart, discount} = ShoppingCart.apply_coupon(cart, "SAVE20")
      assert updated_cart.coupon == "SAVE20"
      assert Decimal.equal?(discount, Decimal.new("60.00"))
    end

    test "returns error for invalid coupon" do
      cart = ShoppingCart.new()
      product = create_product("prod-1", "100.00", 10)
      {:ok, cart} = ShoppingCart.add_item(cart, product, 2)

      assert {:error, :invalid_coupon} = ShoppingCart.apply_coupon(cart, "INVALID")
    end

    test "returns error when minimum not met" do
      cart = ShoppingCart.new()
      product = create_product("prod-1", "10.00", 10)
      {:ok, cart} = ShoppingCart.add_item(cart, product, 1)

      assert {:error, :minimum_not_met} = ShoppingCart.apply_coupon(cart, "SAVE10")
    end

    test "caps discount at 100" do
      cart = ShoppingCart.new()
      product = create_product("prod-1", "100.00", 500)
      {:ok, cart} = ShoppingCart.add_item(cart, product, 50)

      # Subtotal is 50 * 100 * 0.85 (15% bulk discount) = 4250
      # 50% of that is 2125, but we cap at 100
      {:ok, cart, _discount} = ShoppingCart.apply_coupon(cart, "SAVE50")
      discount = ShoppingCart.coupon_discount(cart)
      assert Decimal.equal?(discount, Decimal.new("100"))
    end
  end

  describe "coupon_discount/1" do
    test "returns zero when no coupon applied" do
      cart = ShoppingCart.new()
      product = create_product("prod-1", "100.00", 10)
      {:ok, cart} = ShoppingCart.add_item(cart, product, 2)

      assert Decimal.equal?(ShoppingCart.coupon_discount(cart), Decimal.new("0"))
    end

    test "calculates SAVE10 discount" do
      cart = ShoppingCart.new()
      product = create_product("prod-1", "100.00", 10)
      {:ok, cart} = ShoppingCart.add_item(cart, product, 3)
      {:ok, cart, _} = ShoppingCart.apply_coupon(cart, "SAVE10")

      assert Decimal.equal?(ShoppingCart.coupon_discount(cart), Decimal.new("30.00"))
    end

    test "calculates SAVE50 discount" do
      cart = ShoppingCart.new()
      product = create_product("prod-1", "100.00", 200)
      {:ok, cart} = ShoppingCart.add_item(cart, product, 2)
      {:ok, cart, _} = ShoppingCart.apply_coupon(cart, "SAVE50")

      assert Decimal.equal?(ShoppingCart.coupon_discount(cart), Decimal.new("100.00"))
    end

    test "FREESHIP coupon has zero discount on subtotal" do
      cart = ShoppingCart.new()
      product = create_product("prod-1", "100.00", 10)
      {:ok, cart} = ShoppingCart.add_item(cart, product, 2)
      {:ok, cart, _} = ShoppingCart.apply_coupon(cart, "FREESHIP")

      assert Decimal.equal?(ShoppingCart.coupon_discount(cart), Decimal.new("0"))
    end
  end

  describe "set_shipping_address/2" do
    test "sets valid shipping address" do
      cart = ShoppingCart.new()

      address = %{
        street: "123 Main St",
        city: "San Francisco",
        country: "US",
        postal_code: "94102"
      }

      assert {:ok, cart} = ShoppingCart.set_shipping_address(cart, address)
      assert cart.shipping_address == address
    end

    test "returns error for incomplete address" do
      cart = ShoppingCart.new()
      address = %{street: "123 Main St", city: "San Francisco"}

      assert {:error, :invalid_address} = ShoppingCart.set_shipping_address(cart, address)
    end
  end

  describe "shipping_cost/1" do
    test "returns zero when no shipping address" do
      cart = ShoppingCart.new()
      product = create_product("prod-1", "100.00", 10, weight: 5.0)
      {:ok, cart} = ShoppingCart.add_item(cart, product, 2)

      assert Decimal.equal?(ShoppingCart.shipping_cost(cart), Decimal.new("0"))
    end

    test "calculates shipping for US address" do
      cart = ShoppingCart.new()
      product = create_product("prod-1", "100.00", 10, weight: 3.0)
      {:ok, cart} = ShoppingCart.add_item(cart, product, 2)

      address = %{street: "123 Main", city: "SF", country: "US", postal_code: "94102"}
      {:ok, cart} = ShoppingCart.set_shipping_address(cart, address)

      assert Decimal.equal?(ShoppingCart.shipping_cost(cart), Decimal.new("7.50"))
    end

    test "applies zone multiplier for CA address" do
      cart = ShoppingCart.new()
      product = create_product("prod-1", "100.00", 10, weight: 3.0)
      {:ok, cart} = ShoppingCart.add_item(cart, product, 2)

      address = %{street: "123 Main", city: "Toronto", country: "CA", postal_code: "M5H"}
      {:ok, cart} = ShoppingCart.set_shipping_address(cart, address)

      expected = Decimal.mult(Decimal.new("7.50"), Decimal.new("1.5"))
      assert Decimal.equal?(ShoppingCart.shipping_cost(cart), expected)
    end

    test "FREESHIP coupon makes shipping free" do
      cart = ShoppingCart.new()
      product = create_product("prod-1", "100.00", 10, weight: 5.0)
      {:ok, cart} = ShoppingCart.add_item(cart, product, 2)

      address = %{street: "123 Main", city: "SF", country: "US", postal_code: "94102"}
      {:ok, cart} = ShoppingCart.set_shipping_address(cart, address)
      {:ok, cart, _} = ShoppingCart.apply_coupon(cart, "FREESHIP")

      assert Decimal.equal?(ShoppingCart.shipping_cost(cart), Decimal.new("0"))
    end

    test "calculates shipping for heavy items" do
      cart = ShoppingCart.new()
      product = create_product("prod-1", "100.00", 10, weight: 30.0)
      {:ok, cart} = ShoppingCart.add_item(cart, product, 2)

      address = %{street: "123 Main", city: "SF", country: "US", postal_code: "94102"}
      {:ok, cart} = ShoppingCart.set_shipping_address(cart, address)

      assert Decimal.equal?(ShoppingCart.shipping_cost(cart), Decimal.new("25.00"))
    end
  end

  describe "tax/1" do
    test "calculates tax on taxable items" do
      cart = ShoppingCart.new(tax_rate: Decimal.new("0.10"))
      product = create_product("prod-1", "100.00", 10, taxable: true)
      {:ok, cart} = ShoppingCart.add_item(cart, product, 2)

      assert Decimal.equal?(ShoppingCart.tax(cart), Decimal.new("20.00"))
    end

    test "excludes non-taxable items" do
      cart = ShoppingCart.new(tax_rate: Decimal.new("0.10"))
      product1 = create_product("prod-1", "100.00", 10, taxable: true)
      product2 = create_product("prod-2", "50.00", 10, taxable: false)

      {:ok, cart} = ShoppingCart.add_item(cart, product1, 2)
      {:ok, cart} = ShoppingCart.add_item(cart, product2, 2)

      assert Decimal.equal?(ShoppingCart.tax(cart), Decimal.new("20.00"))
    end

    test "applies tax after coupon discount" do
      cart = ShoppingCart.new(tax_rate: Decimal.new("0.10"))
      product = create_product("prod-1", "100.00", 10, taxable: true)
      {:ok, cart} = ShoppingCart.add_item(cart, product, 2)
      {:ok, cart, _} = ShoppingCart.apply_coupon(cart, "SAVE10")

      expected = Decimal.mult(Decimal.new("180.00"), Decimal.new("0.10"))
      assert Decimal.equal?(ShoppingCart.tax(cart), expected)
    end
  end

  describe "total/1" do
    test "calculates total for simple cart" do
      cart = ShoppingCart.new(tax_rate: Decimal.new("0.10"))
      product = create_product("prod-1", "100.00", 10, taxable: true)
      {:ok, cart} = ShoppingCart.add_item(cart, product, 2)

      address = %{street: "123 Main", city: "SF", country: "US", postal_code: "94102"}
      {:ok, cart} = ShoppingCart.set_shipping_address(cart, address)

      subtotal = Decimal.new("200.00")
      tax = Decimal.new("20.00")
      shipping = Decimal.new("5.00")
      expected = Decimal.add(Decimal.add(subtotal, tax), shipping)

      assert Decimal.equal?(ShoppingCart.total(cart), expected)
    end

    test "calculates total with coupon" do
      cart = ShoppingCart.new(tax_rate: Decimal.new("0.10"))
      product = create_product("prod-1", "100.00", 10, taxable: true)
      {:ok, cart} = ShoppingCart.add_item(cart, product, 3)
      {:ok, cart, _} = ShoppingCart.apply_coupon(cart, "SAVE10")

      address = %{street: "123 Main", city: "SF", country: "US", postal_code: "94102"}
      {:ok, cart} = ShoppingCart.set_shipping_address(cart, address)

      subtotal = Decimal.new("300.00")
      discount = Decimal.new("30.00")
      taxable = Decimal.sub(subtotal, discount)
      tax = Decimal.mult(taxable, Decimal.new("0.10"))
      shipping = Decimal.new("5.00")

      expected =
        subtotal
        |> Decimal.sub(discount)
        |> Decimal.add(shipping)
        |> Decimal.add(tax)

      assert Decimal.equal?(ShoppingCart.total(cart), expected)
    end
  end

  describe "can_checkout?/1" do
    test "returns true when cart has items and address" do
      cart = ShoppingCart.new()
      product = create_product("prod-1", "100.00", 10)
      {:ok, cart} = ShoppingCart.add_item(cart, product, 2)

      address = %{street: "123 Main", city: "SF", country: "US", postal_code: "94102"}
      {:ok, cart} = ShoppingCart.set_shipping_address(cart, address)

      assert ShoppingCart.can_checkout?(cart)
    end

    test "returns false when cart is empty" do
      cart = ShoppingCart.new()

      address = %{street: "123 Main", city: "SF", country: "US", postal_code: "94102"}
      {:ok, cart} = ShoppingCart.set_shipping_address(cart, address)

      refute ShoppingCart.can_checkout?(cart)
    end

    test "returns false when no shipping address" do
      cart = ShoppingCart.new()
      product = create_product("prod-1", "100.00", 10)
      {:ok, cart} = ShoppingCart.add_item(cart, product, 2)

      refute ShoppingCart.can_checkout?(cart)
    end
  end

  describe "summary/1" do
    test "returns complete summary" do
      cart = ShoppingCart.new(tax_rate: Decimal.new("0.10"))
      product = create_product("prod-1", "100.00", 10, taxable: true)
      {:ok, cart} = ShoppingCart.add_item(cart, product, 3)

      address = %{street: "123 Main", city: "SF", country: "US", postal_code: "94102"}
      {:ok, cart} = ShoppingCart.set_shipping_address(cart, address)

      summary = ShoppingCart.summary(cart)

      assert summary.item_count == 3
      assert Decimal.equal?(summary.subtotal, Decimal.new("300.00"))
      assert Decimal.equal?(summary.coupon_discount, Decimal.new("0"))
      assert Decimal.equal?(summary.shipping, Decimal.new("5.00"))
      assert Decimal.equal?(summary.tax, Decimal.new("30.00"))
      assert Decimal.equal?(summary.total, Decimal.new("335.00"))
    end
  end
end
