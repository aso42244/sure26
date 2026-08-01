class AddCadenceToRecurringTransactions < ActiveRecord::Migration[7.2]
  # Lets a recurring income or expense repeat every 14 days instead of monthly.
  # Existing rows default to "monthly" and keep their expected_day_of_month
  # behavior unchanged. Biweekly rows advance by exact 14-day steps from
  # anchor_date; auto-detection remains monthly-only, so only manually created
  # rows use the biweekly cadence.
  def change
    add_column :recurring_transactions, :cadence, :string, null: false, default: "monthly"
    add_column :recurring_transactions, :anchor_date, :date

    add_check_constraint :recurring_transactions,
      "cadence IN ('monthly', 'biweekly')",
      name: "recurring_transactions_cadence_valid"

    add_check_constraint :recurring_transactions,
      "cadence <> 'biweekly' OR anchor_date IS NOT NULL",
      name: "recurring_transactions_biweekly_requires_anchor"
  end
end
