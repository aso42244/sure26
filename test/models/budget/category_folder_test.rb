require "test_helper"

# Coverage for "folder" categories: a non-budgetable top-level category that
# groups its subcategories but has no budget of its own. Its children become
# independent budget lines.
class Budget::CategoryFolderTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @account = accounts(:depository)
    @folder = Category.create!(name: "Folder #{Time.now.to_f}", family: @family, lucide_icon: "shapes", budgetable: false)
    @child_a = Category.create!(name: "ChildA #{Time.now.to_f}", family: @family, parent: @folder)
    @child_b = Category.create!(name: "ChildB #{Time.now.to_f}", family: @family, parent: @folder)
    @budget = Budget.find_or_bootstrap(@family, start_date: Date.current)
    @budget.sync_budget_categories
  end

  def bc(cat)
    @budget.budget_categories.find_by!(category_id: cat.id)
  end

  test "a non-budgetable top-level category is a folder" do
    assert @folder.folder?
    assert bc(@folder).folder?
  end

  test "a subcategory cannot be marked non-budgetable" do
    child = Category.new(name: "X #{Time.now.to_f}", family: @family, parent: @folder, budgetable: false)
    refute child.valid?
    assert child.errors[:budgetable].present?
  end

  test "folder children are independent budget lines, never inheriting" do
    a = bc(@child_a)
    assert a.parent_is_folder?
    assert a.counts_as_budget_root?
    refute a.inherits_parent_budget? # even at $0 default
  end

  test "setting a folder child's budget does not touch the folder parent" do
    bc(@child_a).update_budgeted_spending!(100)
    assert_equal 0, bc(@folder).reload.budgeted_spending
  end

  test "allocated_spending counts folder children, not the folder parent" do
    bc(@child_a).update_budgeted_spending!(100)
    bc(@child_b).update_budgeted_spending!(50)
    @budget.reload

    roots = @budget.budget_categories.select(&:counts_as_budget_root?)
    refute_includes roots.map(&:category_id), @folder.id
    assert_includes roots.map(&:category_id), @child_a.id
    assert_includes roots.map(&:category_id), @child_b.id

    child_total = roots.select { |x| [ @child_a.id, @child_b.id ].include?(x.category_id) }.sum(&:budgeted_spending)
    assert_equal 150, child_total
  end

  test "folder roll-up sums its children's spent, budgeted, and available" do
    bc(@child_a).update_budgeted_spending!(100)
    bc(@child_b).update_budgeted_spending!(50)
    create_transaction(account: @account, amount: 30, date: @budget.start_date + 1, category: @child_a)
    @budget.reload

    folder = bc(@folder)
    assert_equal 150, folder.folder_budgeted
    assert_equal 30, folder.folder_spent
    assert_equal 120, folder.folder_available # 150 budgeted - 30 spent
  end

  test "a folder is placed as an always-visible on-track grouping header" do
    folder = bc(@folder)
    refute folder.any_over_budget?
    assert folder.visible_on_track?
    refute folder.budgeted?
    refute folder.over_budget?
  end
end
