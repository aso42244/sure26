class AddAdjustmentsToBudgetCategoryRollovers < ActiveRecord::Migration[7.2]
  def change
    # Running total of manual money moved into (+) or out of (-) this
    # category's rolled-over balance via a between-category transfer. Kept
    # separate from opening_balance so the rollover roller (which recomputes
    # opening_balance from the prior period every sync) never clobbers a
    # manual transfer.
    add_column :budget_category_rollovers, :adjustments, :decimal, precision: 19, scale: 4, null: false, default: 0
  end
end
