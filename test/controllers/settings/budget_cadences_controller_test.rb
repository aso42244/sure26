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
