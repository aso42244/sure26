require "test_helper"

# Behavior of the Budget model once a family opts into a biweekly cadence.
# Monthly-only behavior is covered by budget_test.rb; here we assert biweekly
# bootstrapping, coexistence with historical monthly budgets, URL params, and
# navigation.
class Budget::BiweeklyTest < ActiveSupport::TestCase
  setup do
    @family = families(:empty)
    @anchor = Date.new(2025, 1, 6)
  end

  def enable_biweekly(effective_from: @anchor, anchor: @anchor)
    @family.budget_schedules.create!(cadence: "biweekly", anchor_date: anchor, effective_from: effective_from)
  end

  test "family without a schedule resolves to monthly (unchanged default)" do
    cadence = @family.budget_cadence_for(Date.new(2025, 3, 15))
    assert cadence.monthly?
    assert_equal [ Date.new(2025, 3, 1), Date.new(2025, 3, 31) ], cadence.period_for(Date.new(2025, 3, 15))
  end

  test "bootstraps a biweekly budget with cadence and anchor when a schedule is active" do
    enable_biweekly
    budget = Budget.find_or_bootstrap(@family, start_date: Date.new(2025, 1, 10))

    assert budget.biweekly?
    assert_equal Date.new(2025, 1, 6), budget.start_date
    assert_equal Date.new(2025, 1, 19), budget.end_date
    assert_equal Date.new(2025, 1, 6), budget.anchor_date
  end

  test "monthly and biweekly budgets coexist across an effective-dated change" do
    # Biweekly only from the anchor forward; earlier dates stay monthly.
    enable_biweekly(effective_from: @anchor)

    historical = Budget.find_or_bootstrap(@family, start_date: Date.new(2024, 11, 15))
    future = Budget.find_or_bootstrap(@family, start_date: Date.new(2025, 1, 10))

    assert historical.monthly?
    assert_equal [ Date.new(2024, 11, 1), Date.new(2024, 11, 30) ], [ historical.start_date, historical.end_date ]
    assert future.biweekly?
    assert_equal [ Date.new(2025, 1, 6), Date.new(2025, 1, 19) ], [ future.start_date, future.end_date ]
  end

  test "biweekly budget uses an unambiguous ISO to_param that round-trips" do
    enable_biweekly
    budget = Budget.find_or_bootstrap(@family, start_date: Date.new(2025, 1, 10))

    assert_equal "2025-01-06", budget.to_param
    round_tripped = Budget.param_to_date(budget.to_param, family: @family)
    assert_equal budget.start_date, Budget.find_or_bootstrap(@family, start_date: round_tripped).start_date
  end

  test "two biweekly cycles in the same month get distinct params" do
    enable_biweekly
    first = Budget.find_or_bootstrap(@family, start_date: Date.new(2025, 1, 6))
    second = Budget.find_or_bootstrap(@family, start_date: Date.new(2025, 1, 20))

    refute_equal first.to_param, second.to_param
    assert_equal "2025-01-06", first.to_param
    assert_equal "2025-01-20", second.to_param
  end

  test "next and previous navigation step by exactly 14 days for biweekly" do
    enable_biweekly
    budget = Budget.find_or_bootstrap(@family, start_date: Date.new(2025, 1, 20))

    assert_equal "2025-02-03", budget.next_budget_param
    assert_equal "2025-01-06", budget.previous_budget_param
  end

  test "existing monthly budgets keep monthly params and navigation" do
    # No schedule: default monthly path is untouched.
    budget = Budget.find_or_bootstrap(@family, start_date: Date.new(2025, 3, 15))
    assert_equal "mar-2025", budget.to_param
    assert_equal "apr-2025", budget.next_budget_param
    assert_equal "feb-2025", budget.previous_budget_param
  end
end
