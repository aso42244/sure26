require "test_helper"

class Settings::BudgetCadencesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @admin = users(:family_admin)
    @family = @admin.family
  end

  test "shows the current cadence" do
    get settings_budget_cadence_url
    assert_response :success
    assert_includes response.body, "Budget cadence"
  end

  test "renders a preview without persisting when preview params are given" do
    assert_no_difference "BudgetSchedule.count" do
      get settings_budget_cadence_url, params: {
        budget_schedule: { cadence: "biweekly", anchor_date: (Date.current + 20).iso8601 }
      }
    end
    assert_response :success
    assert_includes response.body, "Preview"
  end

  test "applies a future-dated biweekly schedule" do
    anchor = Date.current.next_month.beginning_of_month

    assert_difference "@family.budget_schedules.count", 1 do
      post settings_budget_cadence_url, params: {
        budget_schedule: { cadence: "biweekly", anchor_date: anchor.iso8601, effective_from: anchor.iso8601 }
      }
    end

    schedule = @family.budget_schedules.order(:created_at).last
    assert_equal "biweekly", schedule.cadence
    assert_equal anchor, schedule.anchor_date
  end

  test "accepts a change anchored within the current period (starts today or later)" do
    # An anchor inside the current month is fine; the effective date is pinned
    # to today-or-later, so no elapsed period is rewritten.
    anchor = Date.current

    assert_difference "@family.budget_schedules.count", 1 do
      post settings_budget_cadence_url, params: {
        budget_schedule: { cadence: "biweekly", anchor_date: anchor.iso8601 }
      }
    end
    assert_response :redirect

    schedule = @family.budget_schedules.order(:created_at).last
    assert schedule.effective_from >= Date.current
  end

  test "rejects a change with a past effective date" do
    past_effective = Date.current - 30

    assert_no_difference "BudgetSchedule.count" do
      post settings_budget_cadence_url, params: {
        budget_schedule: { cadence: "biweekly", anchor_date: past_effective.iso8601, effective_from: past_effective.iso8601 }
      }
    end
    assert_response :unprocessable_entity
  end

  # The owner must be able to re-pick the anchor date freely. Re-submitting the
  # same anchor used to collide with the pending row ("Effective from has
  # already been taken"); it now replaces it.
  test "re-applying the same anchor replaces the pending change instead of erroring" do
    anchor = Date.current + 5

    post settings_budget_cadence_url, params: {
      budget_schedule: { cadence: "biweekly", anchor_date: anchor.iso8601, effective_from: anchor.iso8601 }
    }
    assert_response :redirect

    assert_no_difference "@family.budget_schedules.count" do
      post settings_budget_cadence_url, params: {
        budget_schedule: { cadence: "biweekly", anchor_date: anchor.iso8601, effective_from: anchor.iso8601 }
      }
    end
    assert_response :redirect
  end

  test "a new anchor supersedes a previously scheduled one" do
    first_anchor = Date.current + 5
    second_anchor = Date.current + 12

    post settings_budget_cadence_url, params: {
      budget_schedule: { cadence: "biweekly", anchor_date: first_anchor.iso8601, effective_from: first_anchor.iso8601 }
    }

    assert_no_difference "@family.budget_schedules.count" do
      post settings_budget_cadence_url, params: {
        budget_schedule: { cadence: "biweekly", anchor_date: second_anchor.iso8601, effective_from: second_anchor.iso8601 }
      }
    end

    schedules = @family.budget_schedules.to_a
    assert_equal 1, schedules.size
    assert_equal second_anchor, schedules.first.anchor_date
  end

  test "a schedule already in effect is preserved when a new change is scheduled" do
    # An in-effect row describes how past periods were generated and must
    # survive; only not-yet-effective rows are superseded.
    in_effect = @family.budget_schedules.create!(
      cadence: "biweekly", anchor_date: Date.current - 28, effective_from: Date.current - 28
    )
    future_anchor = Date.current + 10

    post settings_budget_cadence_url, params: {
      budget_schedule: { cadence: "biweekly", anchor_date: future_anchor.iso8601, effective_from: future_anchor.iso8601 }
    }
    assert_response :redirect

    assert BudgetSchedule.exists?(in_effect.id)
    assert_equal 2, @family.budget_schedules.count
  end

  test "shows a pending scheduled change" do
    anchor = Date.current + 9
    @family.budget_schedules.create!(cadence: "biweekly", anchor_date: anchor, effective_from: anchor)

    get settings_budget_cadence_url

    assert_response :success
    assert_includes response.body, "Scheduled change"
  end

  test "non-admins cannot change cadence" do
    sign_in users(:family_member)

    assert_no_difference "BudgetSchedule.count" do
      post settings_budget_cadence_url, params: {
        budget_schedule: { cadence: "biweekly", anchor_date: Date.current.next_month.iso8601 }
      }
    end
    assert_redirected_to settings_budget_cadence_path
  end
end
