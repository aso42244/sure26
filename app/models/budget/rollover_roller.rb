# Maintains the per-period rollover ledger (BudgetCategoryRollover) for a
# budget. For each rollover-enabled category it:
#
#   1. finalizes the most recent prior period once that period has ended, so
#      closed periods freeze and are never recalculated; and
#   2. creates/refreshes this budget's rollover row, seeding its opening
#      balance from the prior period's closing balance.
#
# The balance therefore chains through the budget periods a family actually
# sets up (the normal navigate / copy-previous flow carries the budgeted
# amount forward). It deliberately does NOT fabricate budgets for cycles the
# user never engaged.
#
# Rollover applies to any category with its own individual budgeted amount --
# a top-level category, or a subcategory once it's been given an individual
# limit (see BudgetCategory#inherits_parent_budget?). A subcategory still
# sharing its parent's pool has no independent figure to roll on its own; it
# already reflects the parent's rollover (if any) through the existing
# shared-pool calc, so it's excluded here to avoid double-tracking the same
# dollars in two ledgers.
class Budget::RolloverRoller
  def self.sync!(budget)
    new(budget).sync!
  end

  def initialize(budget)
    @budget = budget
    @family = budget.family
  end

  def sync!
    categories = budget.budget_categories.select do |bc|
      bc.category_id.present? && !bc.inherits_parent_budget? && (bc.rollover_enabled? || rollover_row_exists?(bc.category_id))
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

      prior = most_recent_prior_rollover(category_id)
      prior.finalize! if prior && !prior.finalized? && prior.budget.end_date < Date.current
      opening = prior ? prior.balance : 0

      rollover = BudgetCategoryRollover.find_or_initialize_by(budget_id: budget.id, category_id: category_id)
      rollover.opening_balance = opening
      rollover.currency = budget.currency if rollover.currency.blank?
      # Reopen nothing: an already-finalized current row keeps its frozen
      # numbers. Only refresh while the period is open.
      unless rollover.finalized?
        rollover.save!
        rollover.finalize! if budget.end_date < Date.current
      end
      rollover
    end

    def most_recent_prior_rollover(category_id)
      BudgetCategoryRollover
        .joins(:budget)
        .where(category_id: category_id, budgets: { family_id: family.id })
        .where("budgets.start_date < ?", budget.start_date)
        .order(Arel.sql("budgets.start_date DESC"))
        .first
    end

    def rollover_row_exists?(category_id)
      BudgetCategoryRollover.exists?(budget_id: budget.id, category_id: category_id)
    end
end
