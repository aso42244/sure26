class CreateBudgetCategoryFunds < ActiveRecord::Migration[7.2]
  # Append-only per-period ledger of a sinking-fund category's accumulated
  # balance. One row per (budget period, category).
  #
  #   closing_balance = opening_balance + contribution - actual_spend
  #   next period's opening_balance = this period's closing_balance
  #
  # A row is frozen (finalized_at set) once its period has ended, so closed
  # periods are never recalculated. The current/open period's actual_spend and
  # closing_balance are computed live from transactions until it finalizes.
  def change
    create_table :budget_category_funds, id: :uuid do |t|
      t.references :budget, null: false, foreign_key: true, type: :uuid
      t.references :category, null: false, foreign_key: true, type: :uuid
      t.decimal :opening_balance, precision: 19, scale: 4, null: false, default: 0
      t.decimal :contribution, precision: 19, scale: 4, null: false, default: 0
      t.decimal :actual_spend, precision: 19, scale: 4
      t.decimal :closing_balance, precision: 19, scale: 4
      t.string :currency, null: false
      t.datetime :finalized_at
      t.timestamps
    end

    add_index :budget_category_funds, %i[budget_id category_id], unique: true
  end
end
