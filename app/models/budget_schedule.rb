# Effective-dated record of the budgeting cadence a family uses to bootstrap
# NEW budget periods. Append-only: a cadence change adds a future-dated row and
# never edits or deletes past rows, so historical periods keep their original
# boundaries (spec: schedule changes are future-only and never rewrite closed
# periods).
#
# A family with no schedule rows behaves as monthly — the upstream default —
# so existing families are unaffected until they explicitly opt in.
class BudgetSchedule < ApplicationRecord
  belongs_to :family

  validates :cadence, presence: true, inclusion: { in: Budget::Cadence::TYPES }
  validates :effective_from, presence: true, uniqueness: { scope: :family_id }
  validates :anchor_date, presence: true, if: :biweekly?
  validate :anchor_date_absent_unless_biweekly

  scope :effective_on_or_before, ->(date) { where("effective_from <= ?", date).order(effective_from: :desc) }

  # Changes that have not started governing budgets yet. Shown in settings so a
  # queued change is visible even while the current cadence still reads as the
  # old one.
  scope :pending, -> { where("effective_from > ?", Date.current).order(:effective_from) }

  # Save this schedule as the family's next cadence change, replacing any change
  # that has not taken effect yet (effective today or later). Rows already in
  # effect before today are never touched, so past periods keep the boundaries
  # they were generated with -- and existing Budget records store their own
  # cadence/anchor anyway, so they are self-describing regardless.
  #
  # This is what lets the anchor date be re-picked freely: a new selection
  # supersedes the previous one instead of colliding with it.
  def supersede_pending!
    result = self.class.transaction do
      scope = family.budget_schedules.where("effective_from >= ?", Date.current)
      scope = scope.where.not(id: id) if persisted?
      scope.destroy_all

      raise ActiveRecord::Rollback unless save

      true
    end

    result.present?
  end

  def biweekly?
    cadence == Budget::Cadence::BIWEEKLY
  end

  def monthly?
    cadence == Budget::Cadence::MONTHLY
  end

  # Build the boundary-math value object for this schedule. `family` is passed
  # through so the monthly path can honor the family's custom month-start day.
  def to_cadence(family: nil)
    Budget::Cadence.new(cadence, anchor_date: anchor_date, family: family || self.family)
  end

  private
    def anchor_date_absent_unless_biweekly
      if !biweekly? && anchor_date.present?
        errors.add(:anchor_date, :must_be_blank_for_monthly)
      end
    end
end
