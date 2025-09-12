class VisitorListener < BaseListener
  # Triggered when the widget is loaded on a page
  # Event payload comes from Api::V1::Widget::EventsController#create
  # with event name 'webwidget.loaded'
  def webwidget_loaded(event)
    contact_inbox = event.data[:contact_inbox]
    return if contact_inbox.blank?

    account = contact_inbox.inbox.account
    # Ensure there is a conversation so that the notification can deep-link
    conversation = contact_inbox.conversations.last
    if conversation.blank?
      conversation = Conversation.create!(
        account_id: account.id,
        inbox_id: contact_inbox.inbox_id,
        contact_id: contact_inbox.contact_id,
        contact_inbox_id: contact_inbox.id,
        additional_attributes: build_additional_attributes(event)
      )
    end

    # Build country flag for the push title
    country_code = fetch_country_code(contact_inbox.contact)
    push_title = "#{to_flag(country_code)} - New visitor".strip

    notify_all_agents(account, conversation, push_title, country_code)
  end

  # Intentionally do not handle webwidget.triggered to avoid click-based notifications

  private

  def build_additional_attributes(event)
    info = event.data[:event_info] || {}
    {
      'browser_language' => info[:browser_language],
      'widget_language' => info[:widget_language],
      'browser' => info[:browser],
      'referer' => info[:referer]
    }.compact
  end

  def notify_all_agents(account, conversation, push_title, country_code)
    # Notify every agent (and administrators) in the account
    account.users.find_each do |user|
      notification = NotificationBuilder.new(
        notification_type: 'conversation_creation',
        user: user,
        account: account,
        primary_actor: conversation
      ).perform

      # Safeguard if for some reason notification couldn't be created
      next if notification.blank?

      # Store override push title and context
      new_meta = (notification.meta || {}).merge(
        'push_title' => push_title,
        'country_code' => country_code
      )
      # rubocop:disable Rails/SkipsModelValidations
      notification.update_column(:meta, new_meta)
      # rubocop:enable Rails/SkipsModelValidations
    end
  end

  def fetch_country_code(contact)
    code = contact.additional_attributes&.dig('country_code') || contact.country_code
    return code if code.present?

    ip = contact.additional_attributes&.dig('updated_at_ip') || contact.additional_attributes&.dig('created_at_ip')
    return if ip.blank?

    result = IpLookupService.new.perform(ip)
    result&.country_code
  rescue StandardError
    nil
  end

  # Convert ISO Alpha-2 code to flag emoji
  def to_flag(code)
    return '' if code.blank?
    code.upcase.chars.map { |ch| (127397 + ch.ord).chr(Encoding::UTF_8) }.join
  end
end

VisitorListener.prepend_mod_with('VisitorListener')


