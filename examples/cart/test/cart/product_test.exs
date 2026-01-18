defmodule Cart.ProductTest do
  use ExUnit.Case, async: true

  alias Cart.Product

  describe "new/1" do
    test "creates a valid product" do
      attrs = %{
        id: "prod-1",
        name: "Laptop",
        price: Decimal.new("999.99"),
        stock: 10,
        category: :electronics,
        weight: 5.5,
        taxable: true
      }

      assert {:ok, product} = Product.new(attrs)
      assert product.id == "prod-1"
      assert product.name == "Laptop"
      assert Decimal.equal?(product.price, Decimal.new("999.99"))
      assert product.stock == 10
    end

    test "returns error for missing required fields" do
      attrs = %{name: "Laptop", price: Decimal.new("999.99")}
      assert {:error, :missing_required_fields} = Product.new(attrs)
    end

    test "returns error for invalid price" do
      attrs = %{
        id: "prod-1",
        name: "Laptop",
        price: Decimal.new("0"),
        stock: 10,
        category: :electronics,
        weight: 5.5,
        taxable: true
      }

      assert {:error, :invalid_price} = Product.new(attrs)
    end

    test "returns error for negative price" do
      attrs = %{
        id: "prod-1",
        name: "Laptop",
        price: Decimal.new("-10"),
        stock: 10,
        category: :electronics,
        weight: 5.5,
        taxable: true
      }

      assert {:error, :invalid_price} = Product.new(attrs)
    end

    test "returns error for negative stock" do
      attrs = %{
        id: "prod-1",
        name: "Laptop",
        price: Decimal.new("999.99"),
        stock: -5,
        category: :electronics,
        weight: 5.5,
        taxable: true
      }

      assert {:error, :invalid_stock} = Product.new(attrs)
    end

    test "returns error for invalid weight" do
      attrs = %{
        id: "prod-1",
        name: "Laptop",
        price: Decimal.new("999.99"),
        stock: 10,
        category: :electronics,
        weight: 0.0,
        taxable: true
      }

      assert {:error, :invalid_weight} = Product.new(attrs)
    end

    test "returns error for empty name" do
      attrs = %{
        id: "prod-1",
        name: "",
        price: Decimal.new("999.99"),
        stock: 10,
        category: :electronics,
        weight: 5.5,
        taxable: true
      }

      assert {:error, :invalid_name} = Product.new(attrs)
    end

    test "returns error for overly long name" do
      attrs = %{
        id: "prod-1",
        name: String.duplicate("a", 201),
        price: Decimal.new("999.99"),
        stock: 10,
        category: :electronics,
        weight: 5.5,
        taxable: true
      }

      assert {:error, :invalid_name} = Product.new(attrs)
    end
  end

  describe "available?/2" do
    setup do
      {:ok, product} =
        Product.new(%{
          id: "prod-1",
          name: "Laptop",
          price: Decimal.new("999.99"),
          stock: 10,
          category: :electronics,
          weight: 5.5,
          taxable: true
        })

      %{product: product}
    end

    test "returns true when stock is sufficient", %{product: product} do
      assert Product.available?(product, 5)
      assert Product.available?(product, 10)
    end

    test "returns false when stock is insufficient", %{product: product} do
      refute Product.available?(product, 11)
      refute Product.available?(product, 100)
    end

    test "returns false for zero or negative quantity", %{product: product} do
      refute Product.available?(product, 0)
      refute Product.available?(product, -1)
    end
  end

  describe "calculate_price/2" do
    setup do
      {:ok, product} =
        Product.new(%{
          id: "prod-1",
          name: "Laptop",
          price: Decimal.new("100.00"),
          stock: 200,
          category: :electronics,
          weight: 5.5,
          taxable: true
        })

      %{product: product}
    end

    test "calculates price without discount for quantity < 5", %{product: product} do
      assert Decimal.equal?(Product.calculate_price(product, 1), Decimal.new("100.00"))
      assert Decimal.equal?(Product.calculate_price(product, 4), Decimal.new("400.00"))
    end

    test "applies 5% discount for quantity >= 5", %{product: product} do
      expected = Decimal.mult(Decimal.new("100.00"), Decimal.new("5"))
      expected = Decimal.mult(expected, Decimal.new("0.95"))
      assert Decimal.equal?(Product.calculate_price(product, 5), expected)
    end

    test "applies 10% discount for quantity >= 10", %{product: product} do
      expected = Decimal.mult(Decimal.new("100.00"), Decimal.new("10"))
      expected = Decimal.mult(expected, Decimal.new("0.90"))
      assert Decimal.equal?(Product.calculate_price(product, 10), expected)
    end

    test "applies 15% discount for quantity >= 50", %{product: product} do
      expected = Decimal.mult(Decimal.new("100.00"), Decimal.new("50"))
      expected = Decimal.mult(expected, Decimal.new("0.85"))
      assert Decimal.equal?(Product.calculate_price(product, 50), expected)
    end

    test "applies 20% discount for quantity >= 100", %{product: product} do
      expected = Decimal.mult(Decimal.new("100.00"), Decimal.new("100"))
      expected = Decimal.mult(expected, Decimal.new("0.80"))
      assert Decimal.equal?(Product.calculate_price(product, 100), expected)
    end
  end

  describe "reduce_stock/2" do
    setup do
      {:ok, product} =
        Product.new(%{
          id: "prod-1",
          name: "Laptop",
          price: Decimal.new("999.99"),
          stock: 10,
          category: :electronics,
          weight: 5.5,
          taxable: true
        })

      %{product: product}
    end

    test "reduces stock successfully", %{product: product} do
      assert {:ok, updated} = Product.reduce_stock(product, 5)
      assert updated.stock == 5
    end

    test "reduces stock to zero", %{product: product} do
      assert {:ok, updated} = Product.reduce_stock(product, 10)
      assert updated.stock == 0
    end

    test "returns error for insufficient stock", %{product: product} do
      assert {:error, :insufficient_stock} = Product.reduce_stock(product, 11)
    end

    test "returns error for zero quantity", %{product: product} do
      assert {:error, :insufficient_stock} = Product.reduce_stock(product, 0)
    end

    test "returns error for negative quantity", %{product: product} do
      assert {:error, :insufficient_stock} = Product.reduce_stock(product, -1)
    end
  end

  describe "restore_stock/2" do
    setup do
      {:ok, product} =
        Product.new(%{
          id: "prod-1",
          name: "Laptop",
          price: Decimal.new("999.99"),
          stock: 10,
          category: :electronics,
          weight: 5.5,
          taxable: true
        })

      %{product: product}
    end

    test "restores stock successfully", %{product: product} do
      assert {:ok, updated} = Product.restore_stock(product, 5)
      assert updated.stock == 15
    end

    test "returns error for zero quantity", %{product: product} do
      assert {:error, :invalid_quantity} = Product.restore_stock(product, 0)
    end

    test "returns error for negative quantity", %{product: product} do
      assert {:error, :invalid_quantity} = Product.restore_stock(product, -1)
    end
  end

  describe "needs_restock?/1" do
    test "returns true for electronics below 10" do
      {:ok, product} =
        Product.new(%{
          id: "prod-1",
          name: "Laptop",
          price: Decimal.new("999.99"),
          stock: 9,
          category: :electronics,
          weight: 5.5,
          taxable: true
        })

      assert Product.needs_restock?(product)
    end

    test "returns false for electronics at or above 10" do
      {:ok, product} =
        Product.new(%{
          id: "prod-1",
          name: "Laptop",
          price: Decimal.new("999.99"),
          stock: 10,
          category: :electronics,
          weight: 5.5,
          taxable: true
        })

      refute Product.needs_restock?(product)
    end

    test "returns true for clothing below 20" do
      {:ok, product} =
        Product.new(%{
          id: "prod-2",
          name: "T-Shirt",
          price: Decimal.new("19.99"),
          stock: 19,
          category: :clothing,
          weight: 0.3,
          taxable: true
        })

      assert Product.needs_restock?(product)
    end

    test "returns true for food below 50" do
      {:ok, product} =
        Product.new(%{
          id: "prod-3",
          name: "Apple",
          price: Decimal.new("1.99"),
          stock: 49,
          category: :food,
          weight: 0.2,
          taxable: false
        })

      assert Product.needs_restock?(product)
    end

    test "returns true for books below 15" do
      {:ok, product} =
        Product.new(%{
          id: "prod-4",
          name: "Novel",
          price: Decimal.new("14.99"),
          stock: 14,
          category: :books,
          weight: 0.8,
          taxable: true
        })

      assert Product.needs_restock?(product)
    end

    test "returns true for other categories below 5" do
      {:ok, product} =
        Product.new(%{
          id: "prod-5",
          name: "Widget",
          price: Decimal.new("9.99"),
          stock: 4,
          category: :other,
          weight: 0.1,
          taxable: true
        })

      assert Product.needs_restock?(product)
    end
  end

  describe "shipping_weight/2" do
    setup do
      {:ok, product} =
        Product.new(%{
          id: "prod-1",
          name: "Laptop",
          price: Decimal.new("999.99"),
          stock: 10,
          category: :electronics,
          weight: 5.5,
          taxable: true
        })

      %{product: product}
    end

    test "calculates shipping weight for single item", %{product: product} do
      assert Product.shipping_weight(product, 1) == 5.5
    end

    test "calculates shipping weight for multiple items", %{product: product} do
      assert Product.shipping_weight(product, 3) == 16.5
    end
  end

  describe "seasonal_discount/2" do
    test "applies 30% discount for clothing in winter" do
      {:ok, product} =
        Product.new(%{
          id: "prod-1",
          name: "Jacket",
          price: Decimal.new("100.00"),
          stock: 10,
          category: :clothing,
          weight: 1.0,
          taxable: true
        })

      result = Product.seasonal_discount(product, :winter)
      assert Decimal.equal?(result, Decimal.new("70.00"))
    end

    test "applies 25% discount for clothing in summer" do
      {:ok, product} =
        Product.new(%{
          id: "prod-1",
          name: "Shorts",
          price: Decimal.new("50.00"),
          stock: 10,
          category: :clothing,
          weight: 0.3,
          taxable: true
        })

      result = Product.seasonal_discount(product, :summer)
      assert Decimal.equal?(result, Decimal.new("37.50"))
    end

    test "applies 40% discount for electronics on black friday" do
      {:ok, product} =
        Product.new(%{
          id: "prod-1",
          name: "TV",
          price: Decimal.new("500.00"),
          stock: 5,
          category: :electronics,
          weight: 15.0,
          taxable: true
        })

      result = Product.seasonal_discount(product, :black_friday)
      assert Decimal.equal?(result, Decimal.new("300.00"))
    end

    test "applies 20% discount for books on back to school" do
      {:ok, product} =
        Product.new(%{
          id: "prod-1",
          name: "Textbook",
          price: Decimal.new("80.00"),
          stock: 20,
          category: :books,
          weight: 2.0,
          taxable: true
        })

      result = Product.seasonal_discount(product, :back_to_school)
      assert Decimal.equal?(result, Decimal.new("64.00"))
    end

    test "applies 50% discount for clearance" do
      {:ok, product} =
        Product.new(%{
          id: "prod-1",
          name: "Item",
          price: Decimal.new("30.00"),
          stock: 3,
          category: :other,
          weight: 1.0,
          taxable: true
        })

      result = Product.seasonal_discount(product, :clearance)
      assert Decimal.equal?(result, Decimal.new("15.00"))
    end

    test "applies no discount for no matching season" do
      {:ok, product} =
        Product.new(%{
          id: "prod-1",
          name: "Item",
          price: Decimal.new("50.00"),
          stock: 10,
          category: :electronics,
          weight: 1.0,
          taxable: true
        })

      result = Product.seasonal_discount(product, :spring)
      assert Decimal.equal?(result, Decimal.new("50.00"))
    end

    test "enforces minimum price of 0.01" do
      {:ok, product} =
        Product.new(%{
          id: "prod-1",
          name: "Cheap Item",
          price: Decimal.new("0.02"),
          stock: 100,
          category: :other,
          weight: 0.1,
          taxable: true
        })

      result = Product.seasonal_discount(product, :clearance)
      assert Decimal.equal?(result, Decimal.new("0.01"))
    end
  end
end
