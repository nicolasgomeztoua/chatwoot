module WebsiteTokenHelper
  def auth_token_params
    @auth_token_params ||= ::Widget::TokenService.new(token: request.headers['X-Auth-Token']).decode_token
  end

  def set_web_widget
    @web_widget = ::Channel::WebWidget.find_by!(website_token: permitted_params[:website_token])
    @current_account = @web_widget.inbox.account

    render json: { error: 'Account is suspended' }, status: :unauthorized unless @current_account.active?
  end

  def set_contact
    @contact_inbox = @web_widget.inbox.contact_inboxes.find_by(
      source_id: auth_token_params[:source_id]
    )
    @contact = @contact_inbox&.contact
    raise ActiveRecord::RecordNotFound unless @contact

    Current.contact = @contact

    # Ensure we always capture latest client IP and trigger lookup for returning users
    if @current_account.feature_enabled?('ip_lookup')
      ip = client_ip
      if ip.present?
        additional = (@contact.additional_attributes || {}).dup
        # Update only when changed or missing
        if additional['updated_at_ip'] != ip && additional['created_at_ip'] != ip
          additional['updated_at_ip'] = ip
          @contact.update!(additional_attributes: additional)
          ContactIpLookupJob.perform_later(@contact)
        end
      end
    end
  end

  def permitted_params
    params.permit(:website_token)
  end

  def client_ip
    forwarded_for = request.headers['X-Forwarded-For']
    return forwarded_for.split(',').first.to_s.strip if forwarded_for.present?

    request.remote_ip
  end
end
