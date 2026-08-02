class ReplaceSinkingFundWithCategoryRollover < ActiveRecord::Migration[7.2]
  # Generalizes the sinking-fund feature into per-category budget rollover: a
  # category's leftover (or overspend) carries into next period's budgeted
  # amount directly, instead of requiring a separate "contribution" field.
  # No contribution data exists yet in any Sure26 deployment, so this is a
  # clean replace rather than a data migration.
  def change
    remove_column :budget_categories, :contribution_amount, :decimal, precision: 19, scale: 4
    add_column :budget_categories, :rollover_enabled, :boolean, default: false, null: false

    drop_table :budget_category_funds do |t|
      t.uuid "budget_id", null: false
      t.uuid "category_id", null: false
      t.decimal "opening_balance", precision: 19, scale: 4, default: "0.0", null: false
      t.decimal "contribution", precision: 19, scale: 4, default: "0.0", null: false
      t.decimal "actual_spend", precision: 19, scale: 4
      t.decimal "closing_balance", precision: 19, scale: 4
      t.string "currency", null: false
      t.datetime "finalized_at"
      t.timestamps
    end

    create_table :budget_category_rollovers, id: :uuid do |t|
      t.references :budget, null: false, foreign_key: true, type: :uuid
      t.references :category, null: false, foreign_key: true, type: :uuid
      t.decimal :opening_balance, precision: 19, scale: 4, default: 0, null: false
      t.decimal :actual_spend, precision: 19, scale: 4
      t.decimal :closing_balance, precision: 19, scale: 4
      t.string :currency, null: false
      t.datetime :finalized_at
      t.timestamps
    end

    add_index :budget_category_rollovers, %i[budget_id category_id], unique: true
  end
end
