require "test_helper"

class BudgetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    sign_in @user
    ensure_tailwind_build
  end

  test "index redirects to the current month budget" do
    get budgets_url

    assert_redirected_to budget_path(Budget.date_to_param(Date.current))
  end

  test "show renders the budget page" do
    get budget_url(Budget.date_to_param(Date.current))

    assert_response :success
  end

  test "show renders a folder category as a collapsible group with a read-only roll-up" do
    family = @user.family
    folder = Category.create!(name: "Folder #{Time.now.to_f}", family: family, lucide_icon: "shapes", budgetable: false)
    child = Category.create!(name: "Child #{Time.now.to_f}", family: family, parent: folder)

    budget = Budget.find_or_bootstrap(family, start_date: Date.current)
    budget.sync_budget_categories
    budget.update!(budgeted_spending: 1000, expected_income: 2000) # initialize the budget
    budget.budget_categories.find_by!(category_id: child.id).update_budgeted_spending!(75)

    get budget_url(Budget.date_to_param(Date.current))

    assert_response :success
    assert_select "[data-controller='budget-folder']", minimum: 1
    assert_includes response.body, folder.name
  end

  test "breadcrumbs include the Plan hub for preview users" do
    @user.update!(preferences: (@user.preferences || {}).merge("preview_features_enabled" => true))

    get budget_url(Budget.date_to_param(Date.current))

    assert_response :success
    assert_select "a[href=?]", plan_path, minimum: 1
  end

  test "renders no Plan links without preview features" do
    get budget_url(Budget.date_to_param(Date.current))

    assert_response :success
    assert_select "a[href=?]", plan_path, count: 0
    assert_select "a[href=?]", budgets_path, minimum: 1
  end

  test "renders a biweekly budget page and picker" do
    anchor = Date.current.beginning_of_week
    @user.family.budget_schedules.create!(cadence: "biweekly", anchor_date: anchor, effective_from: anchor)

    budget = Budget.find_or_bootstrap(@user.family, start_date: Date.current)
    assert budget.biweekly?

    get budget_url(budget.to_param)
    assert_response :success

    get picker_budgets_url(year: budget.start_date.year), headers: { "Turbo-Frame" => "budget_picker" }
    assert_response :success
  end
end
