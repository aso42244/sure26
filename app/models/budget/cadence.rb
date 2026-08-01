# Value object that owns every budget period-boundary and navigation
# calculation. Keeping the math here (rather than scattering `1.month`,
# `14.days`, or monthly conditionals across models, controllers, and views)
# means a future cadence — or a future mobile client — extends one object.
#
# Two cadences are supported:
#   * "monthly"  — the upstream default. Boundaries come from the family
#                  (calendar month, or the family's custom month-start day).
#   * "biweekly" — an exact 14-day cycle generated from an anchor date. The
#                  anchor is the first day of a cycle; the cycle ends 13 days
#                  later. Past and future boundaries are exact 14-day steps
#                  from the anchor, so 27-cycle years, leap years, year
#                  boundaries, and DST changes need no special-casing: the
#                  arithmetic is calendar-date only.
class Budget::Cadence
  class InvalidCadenceError < StandardError; end

  MONTHLY = "monthly"
  BIWEEKLY = "biweekly"
  TYPES = [ MONTHLY, BIWEEKLY ].freeze

  CYCLE_DAYS = 14

  attr_reader :type, :anchor_date, :family

  def self.valid_type?(type)
    TYPES.include?(type.to_s)
  end

  # `anchor_date` is required for biweekly; `family` is used for monthly
  # boundaries (so the family's custom month-start day is honored).
  def initialize(type, anchor_date: nil, family: nil)
    @type = type.to_s
    raise InvalidCadenceError, "Unknown cadence: #{@type}" unless self.class.valid_type?(@type)

    @anchor_date = anchor_date.presence && anchor_date.to_date
    @family = family

    if biweekly? && @anchor_date.nil?
      raise InvalidCadenceError, "Biweekly cadence requires an anchor_date"
    end
  end

  def monthly?
    type == MONTHLY
  end

  def biweekly?
    type == BIWEEKLY
  end

  # [start_date, end_date] of the period that contains `date`.
  def period_for(date)
    date = date.to_date

    if biweekly?
      start_date = cycle_start_on_or_before(date)
      [ start_date, start_date + (CYCLE_DAYS - 1) ]
    elsif family&.uses_custom_month_start?
      [ family.custom_month_start_for(date), family.custom_month_end_for(date) ]
    else
      [ date.beginning_of_month, date.end_of_month ]
    end
  end

  # First day of the period immediately following the one starting on
  # `start_date`. Used for both forward navigation and to derive an end date.
  def next_start(start_date)
    start_date = start_date.to_date
    biweekly? ? start_date + CYCLE_DAYS : (start_date + 1.month)
  end

  # First day of the period immediately preceding the one starting on
  # `start_date`.
  def previous_start(start_date)
    start_date = start_date.to_date
    biweekly? ? start_date - CYCLE_DAYS : (start_date - 1.month)
  end

  # The end date of a period that begins on `start_date`, for this cadence.
  def end_for(start_date)
    biweekly? ? (start_date.to_date + (CYCLE_DAYS - 1)) : period_for(start_date).last
  end

  private
    # Largest cycle start (anchor + 14*n) that is <= date. Uses floored integer
    # division so dates before the anchor step backwards correctly (n negative).
    def cycle_start_on_or_before(date)
      day_offset = (date - anchor_date).to_i
      cycles = day_offset.fdiv(CYCLE_DAYS).floor
      anchor_date + (cycles * CYCLE_DAYS)
    end
end
