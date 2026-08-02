require "test_helper"

# Coverage for manually moving money between budget categories within a
# period (Budget#transfer_category_funds!). The lever differs per category:
# a rollover category moves its accumulated stash (adjustments), a plain
# category moves this period's budgeted amount.
class Budget::CategoryTransferTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @account = accounts(:depository)

    # A far-past anchor is irrelevant here; use a current biweekly period so
    # transfers (current-period-only) are allowed.
    @groceries = Category.create!(name: "Groceries #{Time.now.to_f}", family: @family, lucide_icon: "wallet")
    @car = Category.create!(name: "Car Repairs #{Time.now.to_f}", family: @family, lucide_icon: "car")

    @budget = Budget.find_or_bootstrap(@family, start_date: Date.current)
  end

  def bc(category)
    @budget.budget_categories.find_by!(category_id: category.id)
  end

  test "moves budgeted amount between two non-rollover categories" do
    bc(@groceries).update_budgeted_spending!(500)
    bc(@car).update_budgeted_spending!(100)

    @budget.transfer_category_funds!(from_category_id: @groceries.id, to_category_id: @car.id, amount: 50)

    assert_equal 450, bc(@groceries).budgeted_spending
    assert_equal 150, bc(@car).budgeted_spending
    assert_equal 450, bc(@groceries).available_to_spend
    assert_equal 150, bc(@car).available_to_spend
  end

  test "moves accumulated stash between two rollover categories" do
    g = bc(@groceries)
    g.update_budgeted_spending!(500)
    g.set_rollover_enabled!(true)
    c = bc(@car)
    c.update_budgeted_spending!(100)
    c.set_rollover_enabled!(true)
    @budget.sync_category_rollovers!

    @budget.transfer_category_funds!(from_category_id: @groceries.id, to_category_id: @car.id, amount: 50)

    # Fresh contribution (budgeted) is untouched; the available balance moves.
    assert_equal 500, bc(@groceries).budgeted_spending
    assert_equal 100, bc(@car).budgeted_spending
    assert_equal 450, bc(@groceries).available_to_spend
    assert_equal 150, bc(@car).available_to_spend
  end

  test "can move more than this period's budgeted amount out of an accumulated stash" do
    # Build up a stash across prior closed periods, then move a chunk of it in
    # the current period even though this period only budgets a little.
    family = families(:empty)
    account = Account.create!(family: family, accountable: Depository.new, name: "Checking", status: "active", currency: "USD", balance: 1000)
    savings = Category.create!(name: "Annual Bill #{Time.now.to_f}", family: family, lucide_icon: "wallet")
    other = Category.create!(name: "Vet #{Time.now.to_f}", family: family, lucide_icon: "cat")
    anchor = Date.current - 70 # cycles at -70,-56,-42,-28,-14, and current at 0
    family.budget_schedules.create!(cadence: "biweekly", anchor_date: anchor, effective_from: anchor)

    # Five closed cycles each saving $60 -> $300 stash carried into the current one.
    (0..4).each do |i|
      b = Budget.find_or_bootstrap(family, start_date: anchor + (14 * i))
      row = b.budget_categories.find_by!(category_id: savings.id)
      row.update_budgeted_spending!(60)
      row.set_rollover_enabled!(true)
      b.sync_category_rollovers!
    end

    current = Budget.find_or_bootstrap(family, start_date: Date.current)
    assert current.current?
    csavings = current.budget_categories.find_by!(category_id: savings.id)
    csavings.update_budgeted_spending!(60)
    csavings.set_rollover_enabled!(true)
    cother = current.budget_categories.find_by!(category_id: other.id)
    cother.update_budgeted_spending!(0)
    cother.set_rollover_enabled!(true)
    current.sync_category_rollovers!

    # Opening stash 300 + this cycle's 60 = 360 available. Move 200 out.
    assert_equal 360, csavings.available_to_spend
    current.transfer_category_funds!(from_category_id: savings.id, to_category_id: other.id, amount: 200)

    assert_equal 160, current.budget_categories.find_by!(category_id: savings.id).available_to_spend
    assert_equal 200, current.budget_categories.find_by!(category_id: other.id).available_to_spend
  end

  test "transfer between a rollover and a non-rollover category adjusts each correctly" do
    g = bc(@groceries)
    g.update_budgeted_spending!(500)
    g.set_rollover_enabled!(true)
    @budget.sync_category_rollovers!
    bc(@car).update_budgeted_spending!(100) # non-rollover

    @budget.transfer_category_funds!(from_category_id: @groceries.id, to_category_id: @car.id, amount: 50)

    assert_equal 450, bc(@groceries).available_to_spend # rollover stash lever
    assert_equal 150, bc(@car).budgeted_spending        # budgeted lever
    assert_equal 150, bc(@car).available_to_spend
  end

  test "rejects a non-positive amount" do
    bc(@groceries).update_budgeted_spending!(500)
    bc(@car).update_budgeted_spending!(100)

    assert_raises(Budget::TransferError) do
      @budget.transfer_category_funds!(from_category_id: @groceries.id, to_category_id: @car.id, amount: 0)
    end
    assert_raises(Budget::TransferError) do
      @budget.transfer_category_funds!(from_category_id: @groceries.id, to_category_id: @car.id, amount: -25)
    end
  end

  test "rejects transferring to the same category" do
    bc(@groceries).update_budgeted_spending!(500)

    assert_raises(Budget::TransferError) do
      @budget.transfer_category_funds!(from_category_id: @groceries.id, to_category_id: @groceries.id, amount: 25)
    end
  end

  test "rejects a subcategory still sharing the parent's pool" do
    parent = Category.create!(name: "Parent #{Time.now.to_f}", family: @family, lucide_icon: "wallet")
    child = Category.create!(name: "Child #{Time.now.to_f}", family: @family, parent: parent)
    @budget.sync_budget_categories
    bc(@groceries).update_budgeted_spending!(500)

    child_bc = @budget.budget_categories.find_by!(category_id: child.id)
    assert child_bc.inherits_parent_budget?

    assert_raises(Budget::TransferError) do
      @budget.transfer_category_funds!(from_category_id: @groceries.id, to_category_id: child.id, amount: 25)
    end
  end

  test "allows a subcategory with its own individual limit as an endpoint" do
    parent = Category.create!(name: "Parent #{Time.now.to_f}", family: @family, lucide_icon: "wallet")
    child = Category.create!(name: "Child #{Time.now.to_f}", family: @family, parent: parent)
    @budget.sync_budget_categories
    bc(@groceries).update_budgeted_spending!(500)

    child_bc = @budget.budget_categories.find_by!(category_id: child.id)
    child_bc.update_budgeted_spending!(50)
    refute child_bc.inherits_parent_budget?

    @budget.transfer_category_funds!(from_category_id: @groceries.id, to_category_id: child.id, amount: 25)

    assert_equal 475, bc(@groceries).budgeted_spending
    assert_equal 75, @budget.budget_categories.find_by!(category_id: child.id).budgeted_spending
  end

  test "rejects a transfer in a closed (past) period" do
    family = families(:empty)
    Category.create!(name: "A #{Time.now.to_f}", family: family, lucide_icon: "wallet")
    cat_a = Category.create!(name: "AA #{Time.now.to_f}", family: family, lucide_icon: "wallet")
    cat_b = Category.create!(name: "BB #{Time.now.to_f}", family: family, lucide_icon: "wallet")
    anchor = Date.current - 60
    family.budget_schedules.create!(cadence: "biweekly", anchor_date: anchor, effective_from: anchor)

    past = Budget.find_or_bootstrap(family, start_date: anchor) # fully in the past
    refute past.current?
    past.budget_categories.find_by!(category_id: cat_a.id).update_budgeted_spending!(100)
    past.budget_categories.find_by!(category_id: cat_b.id).update_budgeted_spending!(100)

    assert_raises(Budget::TransferError) do
      past.transfer_category_funds!(from_category_id: cat_a.id, to_category_id: cat_b.id, amount: 25)
    end
  end
end
