# One period's slice of a category's rolled-over balance.
#
#   closing_balance = opening_balance + budgeted_spending - actual_spend
#
# `budgeted_spending` is read live from the linked BudgetCategory for this
# period — there is no separate "contribution" field. A category that is
# never spent from just accumulates its budgeted amount period over period
# (useful for annual/quarterly bills funded a little at a time); a category
# that is overspent carries a negative balance into the next period, which
# is added to whatever is newly budgeted there — positive or negative,
# nothing is auto-adjusted.
#
# A row is frozen (finalized_at set) once its budget period has ended, so a
# closed period's numbers are never recalculated — even if a transaction is
# later backdated into it. The current/open period's actual_spend and
# closing_balance are computed live from transactions until the period rolls.
class BudgetCategoryRollover < ApplicationRecord
  include Monetizable

  belongs_to :budget
  belongs_to :category

  monetize :opening_balance, :actual_spend, :closing_balance, :adjustments

  validates :budget_id, uniqueness: { scope: :category_id }
  validates :opening_balance, presence: true

  def finalized?
    finalized_at.present?
  end

  # Spending charged against this category in its period. Frozen after
  # finalize; otherwise read live from the budget's actuals for this category.
  def spend
    return actual_spend if finalized?
    live_actual_spend
  end

  # The balance carried into the next period. Frozen after finalize.
  # `adjustments` is the running total of manual between-category transfers
  # into (+) or out of (-) this category's stash for the period; it survives
  # the roller's re-seeding of opening_balance.
  def balance
    return closing_balance if finalized?
    (opening_balance || 0) + (adjustments || 0) + live_budgeted_spending - live_actual_spend
  end

  # Freeze this period's actuals and closing balance. Idempotent.
  def finalize!(as_of: Time.current)
    return self if finalized?

    spent = live_actual_spend
    update!(
      actual_spend: spent,
      closing_balance: (opening_balance || 0) + (adjustments || 0) + live_budgeted_spending - spent,
      finalized_at: as_of
    )
    self
  end

  private
    def linked_budget_category
      @linked_budget_category ||= budget.budget_categories.detect { |bc| bc.category_id == category_id } ||
        budget.budget_categories.find_by(category_id: category_id)
    end

    def live_budgeted_spending
      linked_budget_category&.budgeted_spending || 0
    end

    def live_actual_spend
      bc = linked_budget_category
      return 0 unless bc

      budget.budget_category_actual_spending(bc)
    end

    def monetizable_currency
      currency
    end
end
