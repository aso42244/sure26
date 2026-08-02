require "test_helper"

class BudgetScheduleTest < ActiveSupport::TestCase
  setup do
    @family = families(:empty)
  end

  test "monthly schedule is valid without an anchor date" do
    schedule = @family.budget_schedules.build(cadence: "monthly", effective_from: Date.current)
    assert schedule.valid?
  end

  test "biweekly schedule requires an anchor date" do
    schedule = @family.budget_schedules.build(cadence: "biweekly", effective_from: Date.current)
    refute schedule.valid?
    assert schedule.errors[:anchor_date].present?
  end

  test "monthly schedule rejects an anchor date" do
    schedule = @family.budget_schedules.build(cadence: "monthly", anchor_date: Date.current, effective_from: Date.current)
    refute schedule.valid?
    assert schedule.errors[:anchor_date].present?
  end

  test "cadence must be a supported type" do
    schedule = @family.budget_schedules.build(cadence: "weekly", effective_from: Date.current)
    refute schedule.valid?
    assert schedule.errors[:cadence].present?
  end

  test "effective_from is unique per family" do
    @family.budget_schedules.create!(cadence: "monthly", effective_from: Date.new(2025, 1, 1))
    dup = @family.budget_schedules.build(cadence: "biweekly", anchor_date: Date.new(2025, 1, 6), effective_from: Date.new(2025, 1, 1))
    refute dup.valid?
    assert dup.errors[:effective_from].present?
  end

  test "supersede_pending! replaces not-yet-effective rows but keeps in-effect ones" do
    in_effect = @family.budget_schedules.create!(
      cadence: "biweekly", anchor_date: Date.current - 28, effective_from: Date.current - 28
    )
    pending = @family.budget_schedules.create!(
      cadence: "biweekly", anchor_date: Date.current + 3, effective_from: Date.current + 3
    )

    replacement = @family.budget_schedules.build(
      cadence: "biweekly", anchor_date: Date.current + 9, effective_from: Date.current + 9
    )
    assert replacement.supersede_pending!

    assert BudgetSchedule.exists?(in_effect.id)
    refute BudgetSchedule.exists?(pending.id)
    assert replacement.persisted?
  end

  test "supersede_pending! leaves existing rows alone when the new one is invalid" do
    pending = @family.budget_schedules.create!(
      cadence: "biweekly", anchor_date: Date.current + 3, effective_from: Date.current + 3
    )

    invalid = @family.budget_schedules.build(cadence: "biweekly", effective_from: Date.current + 9) # no anchor
    refute invalid.supersede_pending!

    assert BudgetSchedule.exists?(pending.id)
  end

  test "pending scope returns only changes that have not started" do
    @family.budget_schedules.create!(cadence: "biweekly", anchor_date: Date.current - 14, effective_from: Date.current - 14)
    upcoming = @family.budget_schedules.create!(cadence: "biweekly", anchor_date: Date.current + 7, effective_from: Date.current + 7)

    assert_equal [ upcoming.id ], @family.budget_schedules.pending.map(&:id)
  end

  test "to_cadence builds a matching value object" do
    schedule = @family.budget_schedules.build(cadence: "biweekly", anchor_date: Date.new(2025, 1, 6), effective_from: Date.new(2025, 1, 6))
    cadence = schedule.to_cadence
    assert cadence.biweekly?
    assert_equal Date.new(2025, 1, 6), cadence.anchor_date
  end
end
