class Settings::BudgetCadencesController < ApplicationController
  layout "settings"

  before_action :require_admin

  # Shows the family's current budgeting cadence and a form to change it. When
  # preview params are present, also renders a preview of the boundaries the
  # change would produce, without persisting anything.
  def show
    @family = Current.family
    @current_cadence = @family.current_budget_cadence
    @pending_schedules = @family.budget_schedules.pending
    @preview = build_preview
  end

  # Applies a cadence change by scheduling a future-dated budget_schedule row.
  # The new selection supersedes any change that has not taken effect yet, so
  # the anchor date can be re-picked as often as the user likes. Historical and
  # in-progress periods are never rewritten.
  def create
    @family = Current.family
    @current_cadence = @family.current_budget_cadence

    schedule = @family.budget_schedules.new(schedule_params)
    schedule.effective_from = resolved_effective_from(schedule) if schedule.effective_from.blank?

    if schedule.effective_from.present? && !future_effective?(schedule.effective_from)
      @pending_schedules = @family.budget_schedules.pending
      @preview = build_preview
      flash.now[:alert] = t("settings.budget_cadences.not_future")
      return render :show, status: :unprocessable_entity
    end

    if schedule.supersede_pending!
      redirect_to settings_budget_cadence_path, notice: t("settings.budget_cadences.success")
    else
      @pending_schedules = @family.budget_schedules.pending
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

    # The date the new cadence begins. It is always a real period boundary of
    # the NEW cadence, on or after today — so the current partial period keeps
    # its old cadence and no already-elapsed period is ever rewritten.
    #
    # Biweekly: the first cycle start (on the chosen anchor grid) that is not in
    # the past. The anchor can be any date the user likes (e.g. a past payday);
    # only the effective date is pinned to now-or-later.
    # Monthly: the start of the next month-period.
    def resolved_effective_from_for(cadence, anchor)
      if cadence.biweekly? && anchor.present?
        start_date = anchor
        start_date = cadence.next_start(start_date) while start_date < Date.current
        start_date
      else
        current_start, _ = @current_cadence.period_for(Date.current)
        @current_cadence.next_start(current_start)
      end
    end

    # A change may take effect today or later, never in the past (which would
    # reinterpret an already-closed period).
    def future_effective?(date)
      date >= Date.current
    end
end
