# One period's slice of a sinking-fund category's accumulated balance.
#
#   closing_balance = opening_balance + contribution - actual_spend
#
# A row is frozen (finalized_at set) once its budget period has ended, so a
# closed period's numbers are never recalculated — even if a transaction is
# later backdated into it. The current/open period's actual_spend and
# closing_balance are computed live from transactions until the period rolls.
#
# Funding and payment are independent by construction: `contribution` is set
# per budget cycle, while `actual_spend` reflects whatever categorized
# transactions actually posted in the period (a monthly, quarterly, or annual
# bill lands whenever it lands). Surplus therefore stays in the fund and is
# never auto-reduced.
class BudgetCategoryFund < ApplicationRecord
  include Monetizable

  belongs_to :budget
  belongs_to :category

  monetize :opening_balance, :contribution, :actual_spend, :closing_balance

  validates :budget_id, uniqueness: { scope: :category_id }
  validates :opening_balance, :contribution, presence: true

  def finalized?
    finalized_at.present?
  end

  # Spending charged against this fund in its period. Frozen after finalize;
  # otherwise read live from the budget's actuals for this category.
  def spend
    return actual_spend if finalized?
    live_actual_spend
  end

  # The fund balance carried into the next period. Frozen after finalize.
  def balance
    return closing_balance if finalized?
    (opening_balance || 0) + (contribution || 0) - live_actual_spend
  end

  # Freeze this period's actuals and closing balance. Idempotent.
  def finalize!(as_of: Time.current)
    return self if finalized?

    spent = live_actual_spend
    update!(
      actual_spend: spent,
      closing_balance: (opening_balance || 0) + (contribution || 0) - spent,
      finalized_at: as_of
    )
    self
  end

  private
    def live_actual_spend
      budget_category = budget.budget_categories.detect { |bc| bc.category_id == category_id }
      budget_category ||= budget.budget_categories.find_by(category_id: category_id)
      return 0 unless budget_category

      budget.budget_category_actual_spending(budget_category)
    end

    def monetizable_currency
      currency
    end
end
