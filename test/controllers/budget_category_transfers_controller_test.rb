require "test_helper"

class BudgetCategoryTransfersControllerTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper

  setup do
    sign_in users(:family_admin)

    @budget = budgets(:one) # current month -> current period
    @family = @budget.family

    @groceries = Category.create!(name: "Groceries xfer test", family: @family, lucide_icon: "wallet")
    @car = Category.create!(name: "Car xfer test", family: @family, lucide_icon: "car")

    BudgetCategory.create!(budget: @budget, category: @groceries, budgeted_spending: 500, currency: "USD")
    BudgetCategory.create!(budget: @budget, category: @car, budgeted_spending: 100, currency: "USD")
  end

  def bc(category)
    @budget.budget_categories.find_by!(category_id: category.id)
  end

  test "new renders the transfer dialog" do
    get new_budget_budget_category_transfer_path(@budget)
    assert_response :success
  end

  test "create moves money and redirects with a success notice" do
    post budget_budget_category_transfers_path(@budget), params: {
      budget_category_transfer: { from_category_id: @groceries.id, to_category_id: @car.id, amount: 50 }
    }

    assert_redirected_to budget_budget_categories_path(@budget)
    assert_equal 450, bc(@groceries).budgeted_spending
    assert_equal 150, bc(@car).budgeted_spending
  end

  test "create rejects the same source and destination" do
    post budget_budget_category_transfers_path(@budget), params: {
      budget_category_transfer: { from_category_id: @groceries.id, to_category_id: @groceries.id, amount: 50 }
    }

    assert_redirected_to budget_budget_categories_path(@budget)
    assert_equal 500, bc(@groceries).budgeted_spending # unchanged
    follow_redirect!
    assert_response :success
  end

  test "create rejects a subcategory still sharing the parent's pool" do
    parent = Category.create!(name: "Parent xfer test", family: @family, lucide_icon: "wallet")
    child = Category.create!(name: "Child xfer test", family: @family, parent: parent)
    BudgetCategory.create!(budget: @budget, category: parent, budgeted_spending: 300, currency: "USD")
    BudgetCategory.create!(budget: @budget, category: child, budgeted_spending: 0, currency: "USD")

    post budget_budget_category_transfers_path(@budget), params: {
      budget_category_transfer: { from_category_id: @groceries.id, to_category_id: child.id, amount: 50 }
    }

    assert_redirected_to budget_budget_categories_path(@budget)
    assert_equal 500, bc(@groceries).budgeted_spending # unchanged
  end
end
