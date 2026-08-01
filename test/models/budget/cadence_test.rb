require "test_helper"

class Budget::CadenceTest < ActiveSupport::TestCase
  # ---------------------------------------------------------------------------
  # Construction / validation
  # ---------------------------------------------------------------------------
  test "rejects unknown cadence type" do
    assert_raises(Budget::Cadence::InvalidCadenceError) { Budget::Cadence.new("weekly") }
  end

  test "biweekly requires an anchor date" do
    assert_raises(Budget::Cadence::InvalidCadenceError) { Budget::Cadence.new("biweekly") }
  end

  test "valid_type? recognizes only supported cadences" do
    assert Budget::Cadence.valid_type?("monthly")
    assert Budget::Cadence.valid_type?("biweekly")
    refute Budget::Cadence.valid_type?("annual")
  end

  # ---------------------------------------------------------------------------
  # Monthly cadence preserves upstream behavior
  # ---------------------------------------------------------------------------
  test "monthly period_for returns calendar month by default" do
    cadence = Budget::Cadence.new("monthly")
    start_date, end_date = cadence.period_for(Date.new(2025, 3, 17))
    assert_equal Date.new(2025, 3, 1), start_date
    assert_equal Date.new(2025, 3, 31), end_date
  end

  test "monthly navigation steps by one month" do
    cadence = Budget::Cadence.new("monthly")
    assert_equal Date.new(2025, 4, 1), cadence.next_start(Date.new(2025, 3, 1))
    assert_equal Date.new(2025, 2, 1), cadence.previous_start(Date.new(2025, 3, 1))
  end

  # ---------------------------------------------------------------------------
  # Biweekly: exact 14-day cycles from an arbitrary anchor
  # ---------------------------------------------------------------------------
  test "biweekly period is exactly 14 calendar days" do
    anchor = Date.new(2025, 1, 6)
    cadence = Budget::Cadence.new("biweekly", anchor_date: anchor)
    start_date, end_date = cadence.period_for(anchor)
    assert_equal anchor, start_date
    assert_equal Date.new(2025, 1, 19), end_date
    assert_equal 14, (end_date - start_date).to_i + 1
  end

  test "boundary immediately before, on, and after a cycle start" do
    anchor = Date.new(2025, 1, 6)
    cadence = Budget::Cadence.new("biweekly", anchor_date: anchor)

    # Last day of the first cycle
    assert_equal [ anchor, Date.new(2025, 1, 19) ], cadence.period_for(Date.new(2025, 1, 19))
    # First day of the second cycle
    assert_equal [ Date.new(2025, 1, 20), Date.new(2025, 2, 2) ], cadence.period_for(Date.new(2025, 1, 20))
    # Day before the anchor falls in the previous cycle
    assert_equal [ Date.new(2024, 12, 23), Date.new(2025, 1, 5) ], cadence.period_for(Date.new(2025, 1, 5))
  end

  test "dates far before the anchor step backwards on exact 14-day increments" do
    anchor = Date.new(2025, 1, 6)
    cadence = Budget::Cadence.new("biweekly", anchor_date: anchor)
    start_date, end_date = cadence.period_for(Date.new(2024, 1, 1))
    assert_equal 0, (start_date - anchor).to_i % 14
    assert (start_date..end_date).cover?(Date.new(2024, 1, 1))
    assert_equal 14, (end_date - start_date).to_i + 1
  end

  test "arbitrary anchor on a non-Monday, non-first-of-month date" do
    anchor = Date.new(2025, 3, 13) # a Thursday, mid-month
    cadence = Budget::Cadence.new("biweekly", anchor_date: anchor)
    assert_equal [ anchor, Date.new(2025, 3, 26) ], cadence.period_for(anchor)
    assert_equal Date.new(2025, 3, 27), cadence.next_start(anchor)
  end

  test "biweekly navigation steps by exactly 14 days" do
    anchor = Date.new(2025, 1, 6)
    cadence = Budget::Cadence.new("biweekly", anchor_date: anchor)
    assert_equal anchor + 14, cadence.next_start(anchor)
    assert_equal anchor - 14, cadence.previous_start(anchor)
    assert_equal Date.new(2025, 1, 19), cadence.end_for(anchor)
  end

  # ---------------------------------------------------------------------------
  # Calendar edge cases: leap year, year boundary, DST, 27-cycle year
  # ---------------------------------------------------------------------------
  test "cycle spanning Feb 29 in a leap year stays exactly 14 days" do
    anchor = Date.new(2024, 2, 26) # 2024 is a leap year
    cadence = Budget::Cadence.new("biweekly", anchor_date: anchor)
    start_date, end_date = cadence.period_for(Date.new(2024, 2, 29))
    assert_equal anchor, start_date
    assert_equal Date.new(2024, 3, 10), end_date
    assert_equal 14, (end_date - start_date).to_i + 1
  end

  test "cycle spanning a year boundary stays exactly 14 days" do
    anchor = Date.new(2025, 12, 22)
    cadence = Budget::Cadence.new("biweekly", anchor_date: anchor)
    start_date, end_date = cadence.period_for(Date.new(2026, 1, 1))
    assert_equal anchor, start_date
    assert_equal Date.new(2026, 1, 4), end_date
    assert_equal 14, (end_date - start_date).to_i + 1
  end

  test "cycle spanning a spring-forward DST change stays exactly 14 calendar days" do
    # US DST spring-forward 2025 was March 9; date-only math must be unaffected.
    anchor = Date.new(2025, 3, 3)
    cadence = Budget::Cadence.new("biweekly", anchor_date: anchor)
    start_date, end_date = cadence.period_for(Date.new(2025, 3, 9))
    assert_equal anchor, start_date
    assert_equal Date.new(2025, 3, 16), end_date
    assert_equal 14, (end_date - start_date).to_i + 1
  end

  test "a calendar year can contain 27 cycle starts" do
    # With an early-January anchor, 2026 has 27 cycle starts (spec requirement:
    # never assume 26 per year).
    anchor = Date.new(2026, 1, 1)
    cadence = Budget::Cadence.new("biweekly", anchor_date: anchor)

    starts = []
    current = anchor
    while current.year == 2026
      starts << current
      current = cadence.next_start(current)
    end

    assert_equal 27, starts.length
    assert_equal Date.new(2026, 1, 1), starts.first
    assert_equal Date.new(2026, 12, 31), starts.last
  end

  test "count of cycle starts varies year to year (no fixed 26)" do
    anchor = Date.new(2025, 6, 15)
    cadence = Budget::Cadence.new("biweekly", anchor_date: anchor)

    # Walk cycle starts continuously across a long span and tally by year so
    # boundary cycles are never double-counted or dropped.
    tally = Hash.new(0)
    current = cadence.period_for(Date.new(2024, 1, 1)).first
    current = cadence.next_start(current) while current < Date.new(2024, 1, 1)
    while current <= Date.new(2035, 12, 31)
      tally[current.year] += 1
      current = cadence.next_start(current)
    end

    counts = (2024..2035).map { |y| tally[y] }
    assert counts.all? { |c| [ 26, 27 ].include?(c) }, "every year should have 26 or 27 cycle starts, got #{counts.inspect}"
    assert counts.include?(27), "a long span must contain a 27-cycle year"
  end
end
