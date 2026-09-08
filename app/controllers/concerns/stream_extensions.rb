module StreamExtensions
  extend ActiveSupport::Concern

  def stream_redirect_to(path, notice: nil, alert: nil)
    custom_stream_redirect(path, notice: notice, alert: alert)
  end

  def stream_redirect_back_or_to(path, notice: nil, alert: nil)
    custom_stream_redirect(path, redirect_back: true, notice: notice, alert: alert)
  end

  def refresh_after_destroy(fallback_path, notice:)
    respond_to do |format|
      format.html { redirect_back_or_to fallback_path, notice: notice, status: :see_other }
      format.turbo_stream do
        flash[:notice] = notice
        render turbo_stream: turbo_stream.action(:refresh_page, nil)
      end
    end
  end

  private
    def custom_stream_redirect(path, redirect_back: false, notice: nil, alert: nil)
      flash[:notice] = notice if notice.present?
      flash[:alert] = alert if alert.present?

      redirect_target_url = if redirect_back
        request.referer.presence || path
      else
        path
      end

      render turbo_stream: turbo_stream.action(:redirect, redirect_target_url)
    end
end
