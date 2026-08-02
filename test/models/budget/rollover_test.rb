require "test_helper"

# Integration coverage for budget category rollover. Real categorized
# transactions drive actual spend (spec: actuals must affect the balance
# through the same mechanisms as regular budgets).
class Budget::RolloverTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @account = accounts(:depository)
    @category = Category.create!(name: "Rollover Test #{Time.now.to_f}", family: @family, lucide_icon: "wallet")

    @anchor = Date.current - 30
    @family.budget_schedules.create!(cadence: "biweekly", anchor_date: @anchor, effective_from: @anchor)
  end

  def cycle_budget(index)
    start = @anchor + (14 * index)
    Budget.find_or_bootstrap(@family, start_date: start)
  end

  def set_budgeted_and_rollover(budget, amount, rollover: true)
    bc = budget.budget_categories.find_by!(category_id: @category.id)
    bc.update_budgeted_spending!(amount)
    bc.set_rollover_enabled!(rollover) if rollover && !bc.rollover_enabled?
    budget.reload
  end

  # Owner's example 1: $500 budgeted, $400 spent -> next period starts with
  # $600 available ($500 new budget + $100 carried surplus).
  test "underspending carries a positive surplus into the next period" do
    payment_date = @anchor + 5
    create_transaction(account: @account, amount: 400, date: payment_date, category: @category)

    c1 = cycle_budget(0)
    set_budgeted_and_rollover(c1, 500)
    c1.sync_category_rollovers!

    c2 = cycle_budget(1)
    set_budgeted_and_rollover(c2, 500)
    c2.sync_category_rollovers!

    bc1 = c1.budget_categories.find_by!(category_id: @category.id)
    bc2 = c2.budget_categories.find_by!(category_id: @category.id)

    assert_equal 100, bc1.available_to_spend # 500 - 400
    assert_equal 600, bc2.available_to_spend # 500 + 100 carried
  end

  # Owner's example 2: $75 budgeted, $175 spent -> -$100. Next period adds
  # $75 -> -$25, without any spending yet in that new period.
  test "overspending carries a negative balance into the next period" do
    payment_date = @anchor + 5
    create_transaction(account: @account, amount: 175, date: payment_date, category: @category)

    c1 = cycle_budget(0)
    set_budgeted_and_rollover(c1, 75)
    c1.sync_category_rollovers!

    c2 = cycle_budget(1)
    set_budgeted_and_rollover(c2, 75)
    c2.sync_category_rollovers!

    bc1 = c1.budget_categories.find_by!(category_id: @category.id)
    bc2 = c2.budget_categories.find_by!(category_id: @category.id)

    assert_equal(-100, bc1.available_to_spend)
    assert bc1.over_budget?
    assert_equal(-25, bc2.available_to_spend) # 75 + (-100), no new spend yet
    assert bc2.over_budget?
  end

  # Owner's example 3: fund an annual $260 bill by setting budgeted_spending
  # to $10/cycle and letting it accumulate across many unspent periods.
  # Uses its own family and a far-past anchor so all 5 cycles are safely
  # closed (not the still-open current period) when finalized.
  test "small per-cycle budgeted amounts accumulate toward a large periodic expense" do
    family = families(:empty)
    account = Account.create!(family: family, accountable: Depository.new, name: "Checking", status: "active", currency: "USD", balance: 1000)
    category = Category.create!(name: "Annual Bill #{Time.now.to_f}", family: family, lucide_icon: "wallet")
    anchor = Date.current - 100
    family.budget_schedules.create!(cadence: "biweekly", anchor_date: anchor, effective_from: anchor)

    budget_for = ->(i) { Budget.find_or_bootstrap(family, start_date: anchor + (14 * i)) }

    (0..3).each do |i|
      budget = budget_for.call(i)
      bc = budget.budget_categories.find_by!(category_id: category.id)
      bc.update_budgeted_spending!(10)
      bc.set_rollover_enabled!(true)
      budget.sync_category_rollovers!
    end

    # Cycle 4: the annual bill posts, covered by the accumulated balance.
    bill_date = anchor + (14 * 4) + 2
    create_transaction(account: account, amount: 40, date: bill_date, category: category)

    c5 = budget_for.call(4)
    bc5 = c5.budget_categories.find_by!(category_id: category.id)
    bc5.update_budgeted_spending!(10)
    bc5.set_rollover_enabled!(true)
    c5.sync_category_rollovers!

    # Opening balance from 4 prior unspent cycles (40) + this cycle's 10 - the 40 bill = 10
    assert_equal 10, bc5.available_to_spend
  end

  test "later contributions are not reduced when a category is ahead of schedule" do
    c1 = cycle_budget(0)
    set_budgeted_and_rollover(c1, 100)
    c1.sync_category_rollovers!

    c2 = cycle_budget(1)
    set_budgeted_and_rollover(c2, 100)
    c2.sync_category_rollovers!

    bc2 = c2.budget_categories.find_by!(category_id: @category.id)
    assert_equal 200, bc2.available_to_spend
  end

  test "closed period stays frozen when a transaction is backdated into it" do
    c1 = cycle_budget(0)
    set_budgeted_and_rollover(c1, 150)
    c1.sync_category_rollovers! # finalizes cycle 1 with spend 0

    rollover1 = BudgetCategoryRollover.find_by!(budget_id: c1.id, category_id: @category.id)
    assert rollover1.finalized?
    assert_equal 150, rollover1.closing_balance

    create_transaction(account: @account, amount: 75, date: @anchor + 3, category: @category)
    c1.reload.sync_category_rollovers!

    assert_equal 0, rollover1.reload.actual_spend
    assert_equal 150, rollover1.closing_balance
  end

  test "categories without rollover enabled never create a ledger row" do
    budget = cycle_budget(0)
    bc = budget.budget_categories.find_by!(category_id: @category.id)
    bc.update!(budgeted_spending: 500)
    budget.sync_category_rollovers!

    refute BudgetCategoryRollover.exists?(budget_id: budget.id, category_id: @category.id)
    refute budget.any_rollover_categories?
    assert_equal 500 - bc.actual_spending, bc.available_to_spend
  end

  test "rollover works the same for monthly cadence budgets" do
    monthly_family = families(:empty)
    category = Category.create!(name: "Monthly Rollover #{Time.now.to_f}", family: monthly_family, lucide_icon: "wallet")
    account = Account.create!(family: monthly_family, accountable: Depository.new, name: "Checking", status: "active", currency: "USD", balance: 1000)

    Entry.create!(
      account: account, entryable: Transaction.new(category: category),
      date: 2.months.ago.beginning_of_month + 3, name: "Spend", amount: 150, currency: "USD"
    )

    m1 = Budget.find_or_bootstrap(monthly_family, start_date: 2.months.ago)
    assert m1.monthly?
    bc1 = m1.budget_categories.find_by!(category_id: category.id)
    bc1.update_budgeted_spending!(200)
    bc1.set_rollover_enabled!(true)
    m1.sync_category_rollovers!

    m2 = Budget.find_or_bootstrap(monthly_family, start_date: 1.month.ago)
    bc2 = m2.budget_categories.find_by!(category_id: category.id)
    bc2.update_budgeted_spending!(200)
    bc2.set_rollover_enabled!(true)
    m2.sync_category_rollovers!

    assert_equal 250, bc2.available_to_spend # 200 + (200-150) carried
  end

  test "rollover is not offered for subcategories" do
    parent = Category.create!(name: "Parent #{Time.now.to_f}", family: @family, lucide_icon: "wallet")
    child = Category.create!(name: "Child #{Time.now.to_f}", family: @family, parent: parent)

    budget = cycle_budget(0)
    child_bc = budget.budget_categories.find_by!(category_id: child.id)
    child_bc.update!(budgeted_spending: 50)
    child_bc.set_rollover_enabled!(true)
    budget.sync_category_rollovers!

    # Subcategory pooling still applies -- rollover is a no-op for it.
    refute child_bc.rollover
    refute BudgetCategoryRollover.exists?(budget_id: budget.id, category_id: child.id)
  end
end
