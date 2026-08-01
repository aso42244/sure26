class AddCadenceToBudgets < ActiveRecord::Migration[7.2]
  def change
    # Existing budgets are monthly; the default keeps every current row and any
    # lazily-bootstrapped historical period behaving exactly as before.
    add_column :budgets, :cadence, :string, null: false, default: "monthly"
    # Only populated for biweekly budgets: the first day of a 14-day cycle.
    add_column :budgets, :anchor_date, :date

    add_check_constraint :budgets,
      "cadence IN ('monthly', 'biweekly')",
      name: "budgets_cadence_valid"

    # A biweekly budget is meaningless without the anchor that generates its
    # 14-day boundaries; monthly budgets must not carry one.
    add_check_constraint :budgets,
      "(cadence = 'biweekly' AND anchor_date IS NOT NULL) OR " \
      "(cadence <> 'biweekly' AND anchor_date IS NULL)",
      name: "budgets_anchor_matches_cadence"
  end
end
