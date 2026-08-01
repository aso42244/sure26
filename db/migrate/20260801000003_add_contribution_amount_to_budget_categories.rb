class AddContributionAmountToBudgetCategories < ActiveRecord::Migration[7.2]
  # Optional per-cycle funding amount. NULL (the default for every existing row)
  # means the category is a plain budget line with no sinking-fund behavior, so
  # current budgets are unaffected. A present value turns the category into a
  # sinking fund whose surplus accumulates across periods via budget_category_funds.
  def change
    add_column :budget_categories, :contribution_amount, :decimal, precision: 19, scale: 4
  end
end
