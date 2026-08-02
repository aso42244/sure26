class BudgetCategoryTransfersController < ApplicationController
  before_action :set_budget

  def new
    @transferable_budget_categories = @budget.transferable_budget_categories
  end

  def create
    @budget.transfer_category_funds!(
      from_category_id: transfer_params[:from_category_id],
      to_category_id: transfer_params[:to_category_id],
      amount: transfer_params[:amount]
    )

    redirect_to budget_budget_categories_path(@budget),
      notice: t("budget_category_transfers.create.success")
  rescue Budget::TransferError => e
    redirect_to budget_budget_categories_path(@budget),
      alert: t("budget_category_transfers.create.errors.#{e.message}",
               default: t("budget_category_transfers.create.errors.generic"))
  end

  private
    def transfer_params
      params.require(:budget_category_transfer).permit(:from_category_id, :to_category_id, :amount)
    end

    def set_budget
      start_date = Budget.param_to_date(params[:budget_month_year], family: Current.family)
      @budget = Current.family.budgets.find_by!(start_date: start_date)
    end
end
