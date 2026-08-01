require "test_helper"

# Integration coverage for the sinking-fund accumulation ledger. Real
# categorized transactions drive actual spend (spec #14: actuals must affect
# the accumulated balance through the same mechanisms as regular budgets).
class Budget::FundTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @account = accounts(:depository)
    @category = Category.create!(name: "Insurance #{Time.now.to_f}", family: @family, lucide_icon: "shield")

    # Biweekly from 30 days ago: cycle 1 and 2 are fully in the past (they
    # finalize on sync), cycle 3 contains today (stays open / live).
    @anchor = Date.current - 30
    @family.budget_schedules.create!(cadence: "biweekly", anchor_date: @anchor, effective_from: @anchor)
  end

  def cycle_budget(index)
    start = @anchor + (14 * index)
    Budget.find_or_bootstrap(@family, start_date: start)
  end

  def set_contribution(budget, amount)
    bc = budget.budget_categories.find_by!(category_id: @category.id)
    bc.update_contribution!(amount)
    budget.reload
  end

  test "a single period fund equals its contribution when nothing is spent" do
    budget = cycle_budget(2) # current, open period
    set_contribution(budget, 150)

    fund = BudgetCategoryFund.find_by!(budget_id: budget.id, category_id: @category.id)
    assert_equal 0, fund.opening_balance
    assert_equal 150, fund.contribution
    assert_equal 150, fund.balance
  end

  test "balance accumulates across periods and retains a third-paycheck surplus" do
    # $150 contributed every cycle; a single $300 payment posts in cycle 2.
    payment_date = @anchor + 14 + 5 # inside cycle 2
    create_transaction(account: @account, amount: 300, date: payment_date, category: @category)

    c1 = cycle_budget(0)
    set_contribution(c1, 150)
    c1.sync_category_funds!

    c2 = cycle_budget(1)
    set_contribution(c2, 150)
    c2.sync_category_funds!

    c3 = cycle_budget(2)
    set_contribution(c3, 150)
    c3.sync_category_funds!

    f1 = BudgetCategoryFund.find_by!(budget_id: c1.id, category_id: @category.id)
    f2 = BudgetCategoryFund.find_by!(budget_id: c2.id, category_id: @category.id)
    f3 = BudgetCategoryFund.find_by!(budget_id: c3.id, category_id: @category.id)

    # Cycle 1: 0 + 150 - 0 = 150 (frozen, past)
    assert f1.finalized?
    assert_equal 150, f1.closing_balance

    # Cycle 2: 150 + 150 - 300 = 0 (frozen, past)
    assert f2.finalized?
    assert_equal 300, f2.actual_spend
    assert_equal 0, f2.closing_balance

    # Cycle 3: 0 + 150 - 0 = 150 retained surplus (open, live)
    refute f3.finalized?
    assert_equal 0, f3.opening_balance
    assert_equal 150, f3.balance
  end

  test "later contributions are not reduced when the fund is ahead of schedule" do
    # No spending at all: every cycle still contributes its full amount and the
    # balance keeps growing (no auto-reduction).
    c1 = cycle_budget(0)
    set_contribution(c1, 100)
    c1.sync_category_funds!

    c2 = cycle_budget(1)
    set_contribution(c2, 100)
    c2.sync_category_funds!

    f2 = BudgetCategoryFund.find_by!(budget_id: c2.id, category_id: @category.id)
    assert_equal 100, f2.contribution
    assert_equal 100, f2.opening_balance
    assert_equal 200, f2.balance
  end

  test "closed period stays frozen when a transaction is backdated into it" do
    c1 = cycle_budget(0)
    set_contribution(c1, 150)
    c1.sync_category_funds! # finalizes cycle 1 with spend 0

    f1 = BudgetCategoryFund.find_by!(budget_id: c1.id, category_id: @category.id)
    assert f1.finalized?
    assert_equal 150, f1.closing_balance

    # Backdate a payment into the already-closed cycle 1.
    create_transaction(account: @account, amount: 75, date: @anchor + 3, category: @category)
    c1.reload.sync_category_funds!

    # The frozen closed period is not recalculated.
    assert_equal 0, f1.reload.actual_spend
    assert_equal 150, f1.closing_balance
  end

  test "non-fund categories never create ledger rows" do
    budget = cycle_budget(2)
    # A category with a normal budgeted_spending but no contribution.
    bc = budget.budget_categories.find_by!(category_id: @category.id)
    bc.update!(budgeted_spending: 500)
    budget.sync_category_funds!

    refute BudgetCategoryFund.exists?(budget_id: budget.id, category_id: @category.id)
    refute budget.any_sinking_funds?
  end
end
