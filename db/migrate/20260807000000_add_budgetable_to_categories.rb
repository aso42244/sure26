class AddBudgetableToCategories < ActiveRecord::Migration[7.2]
  def change
    # A non-budgetable top-level category is a "folder": a pure grouping header
    # with no budget of its own. Its subcategories become independent budget
    # lines. Defaults to true so every existing category keeps behaving exactly
    # as before.
    add_column :categories, :budgetable, :boolean, null: false, default: true
  end
end
