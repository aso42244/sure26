class CreateBudgetSchedules < ActiveRecord::Migration[7.2]
  # Effective-dated record of the cadence a family uses to bootstrap NEW budget
  # periods. Append-only: changing cadence adds a future-dated row and never
  # rewrites past rows, so historical periods keep their original boundaries.
  # A family with no rows behaves as monthly (the upstream default).
  def change
    create_table :budget_schedules, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.string :cadence, null: false, default: "monthly"
      t.date :anchor_date
      t.date :effective_from, null: false
      t.timestamps
    end

    add_index :budget_schedules, %i[family_id effective_from], unique: true

    add_check_constraint :budget_schedules,
      "cadence IN ('monthly', 'biweekly')",
      name: "budget_schedules_cadence_valid"

    add_check_constraint :budget_schedules,
      "(cadence = 'biweekly' AND anchor_date IS NOT NULL) OR " \
      "(cadence <> 'biweekly' AND anchor_date IS NULL)",
      name: "budget_schedules_anchor_matches_cadence"
  end
end
