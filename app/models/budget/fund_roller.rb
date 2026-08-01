# Maintains the per-period sinking-fund ledger (BudgetCategoryFund) for a
# budget. For each sinking-fund category it:
#
#   1. finalizes the most recent prior period once that period has ended, so
#      closed periods freeze and are never recalculated; and
#   2. creates/refreshes this budget's fund row, seeding its opening balance
#      from the prior period's closing balance and its contribution from the
#      category's per-cycle contribution amount.
#
# The accumulated balance therefore chains through the budget periods a family
# actually sets up (the normal navigate / copy-previous flow carries the
# contribution forward). It deliberately does NOT fabricate budgets for cycles
# the user never engaged — contributions are user-entered per period, so an
# un-created period contributes nothing.
class Budget::FundRoller
  def self.sync!(budget)
    new(budget).sync!
  end

  def initialize(budget)
    @budget = budget
    @family = budget.family
  end

  def sync!
    categories = budget.budget_categories.select do |bc|
      bc.category_id.present? && (bc.sinking_fund? || fund_row_exists?(bc.category_id))
    end
    return if categories.empty?

    Budget.transaction do
      categories.each { |bc| sync_category(bc) }
    end
  end

  private
    attr_reader :budget, :family

    def sync_category(budget_category)
      category_id = budget_category.category_id

      prior = most_recent_prior_fund(category_id)
      prior.finalize! if prior && !prior.finalized? && prior.budget.end_date < Date.current
      opening = prior ? prior.balance : 0

      fund = BudgetCategoryFund.find_or_initialize_by(budget_id: budget.id, category_id: category_id)
      fund.opening_balance = opening
      fund.contribution = budget_category.contribution_amount || 0
      fund.currency = budget.currency if fund.currency.blank?
      # Reopen nothing: an already-finalized current row keeps its frozen
      # numbers. Only refresh while the period is open.
      unless fund.finalized?
        fund.save!
        fund.finalize! if budget.end_date < Date.current
      end
      fund
    end

    def most_recent_prior_fund(category_id)
      BudgetCategoryFund
        .joins(:budget)
        .where(category_id: category_id, budgets: { family_id: family.id })
        .where("budgets.start_date < ?", budget.start_date)
        .order(Arel.sql("budgets.start_date DESC"))
        .first
    end

    def fund_row_exists?(category_id)
      BudgetCategoryFund.exists?(budget_id: budget.id, category_id: category_id)
    end
end
