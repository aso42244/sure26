class Settings::BudgetCadencesController < ApplicationController
  layout "settings"

  before_action :require_admin

  # Shows the family's current budgeting cadence and a form to change it. When
  # preview params are present, also renders a preview of the boundaries the
  # change would produce, without persisting anything.
  def show
    @family = Current.family
    @current_cadence = @family.current_budget_cadence
    @preview = build_preview
  end

  # Applies a cadence change by appending a future-dated budget_schedule row.
  # Historical and current periods are never rewritten.
  def create
    @family = Current.family
    @current_cadence = @family.current_budget_cadence

    schedule = @family.budget_schedules.new(schedule_params)
    schedule.effective_from = resolved_effective_from(schedule) if schedule.effective_from.blank?

    if schedule.effective_from.present? && !future_effective?(schedule.effective_from)
      @preview = build_preview
      flash.now[:alert] = t("settings.budget_cadences.not_future")
      return render :show, status: :unprocessable_entity
    end

    if schedule.save
      redirect_to settings_budget_cadence_path, notice: t("settings.budget_cadences.success")
    else
      @preview = build_preview
      flash.now[:alert] = schedule.errors.full_messages.to_sentence
      render :show, status: :unprocessable_entity
    end
  end

  private
    def require_admin
      unless Current.user.admin?
        redirect_to settings_budget_cadence_path, alert: t("settings.budget_cadences.admin_only")
      end
    end

    def schedule_params
      params.fetch(:budget_schedule, {}).permit(:cadence, :anchor_date, :effective_from)
    end

    def cadence_param
      schedule_params[:cadence]
    end

    def anchor_param
      Date.parse(schedule_params[:anchor_date]) if schedule_params[:anchor_date].present?
    rescue ArgumentError
      nil
    end

    # A non-persisted view of what the requested change would produce: the
    # current period, the first new period, and the one after it. Returns nil
    # when there is nothing valid to preview yet.
    def build_preview
      return nil unless Budget::Cadence.valid_type?(cadence_param)

      anchor = anchor_param
      return nil if cadence_param == Budget::Cadence::BIWEEKLY && anchor.nil?

      cadence = Budget::Cadence.new(cadence_param, anchor_date: anchor, family: @family)
      effective_from = resolved_effective_from_for(cadence, anchor)

      basis = [ effective_from, Date.current ].compact.max
      first_start, first_end = cadence.period_for(basis)
      next_start = cadence.next_start(first_start)

      {
        cadence: cadence,
        effective_from: effective_from,
        current_period: @current_cadence.period_for(Date.current),
        first_period: [ first_start, first_end ],
        next_period: [ next_start, cadence.end_for(next_start) ]
      }
    end

    def resolved_effective_from(schedule)
      resolved_effective_from_for(schedule.to_cadence(family: @family), schedule.anchor_date)
    end

    # Default a change to the start of the next period, so it only affects the
    # future and never the period already in progress.
    def resolved_effective_from_for(cadence, anchor)
      if cadence.biweekly? && anchor.present?
        [ anchor, Date.current.tomorrow ].max
      else
        current_start, _ = @current_cadence.period_for(Date.current)
        @current_cadence.next_start(current_start)
      end
    end

    def future_effective?(date)
      _current_start, current_end = @current_cadence.period_for(Date.current)
      date > current_end
    end
end
