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
        additional_attributes: build_additional_attributes(event),
        status: :pending
      )
    end

    # Mark as visitor-loaded and persist best-effort location for reliability
    country_code = fetch_country_code(contact_inbox.contact)
    add_visitor_marker(conversation, country_code)
    persist_country_if_missing(contact_inbox.contact, country_code)
    notify_all_agents(conversation.inbox.account, conversation)
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

  def add_visitor_marker(conversation, country_code)
    attrs = conversation.additional_attributes || {}
    attrs['visitor_loaded'] = true
    attrs['visitor_country_code'] = country_code if country_code.present?
    # rubocop:disable Rails/SkipsModelValidations
    conversation.update_column(:additional_attributes, attrs)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def persist_country_if_missing(contact, country_code)
    return if country_code.blank?

    additional = (contact.additional_attributes || {}).dup
    changed = false
    if additional['country_code'].blank?
      additional['country_code'] = country_code
      changed = true
    end
    if changed
      contact.update!(additional_attributes: additional)
      attach_country_flag_avatar(contact, country_code)
    end
  end

  # Downloads flag image and attaches it as the contact avatar if none present
  def attach_country_flag_avatar(contact, country_code)
    return if contact.avatar.attached?

    code = country_code.to_s.upcase
    return if code.blank?

    # Use FlagsAPI flat 64px PNG as source and store with deterministic filename
    # Ref: https://flagsapi.com/
    flag_url = "https://flagsapi.com/#{code}/flat/64.png"
    preferred_filename = "flag_#{code}.png"
    Avatar::AvatarFromUrlJob.perform_later(contact, flag_url, preferred_filename)
  end

  def notify_all_agents(account, conversation)
    account.users.find_each do |user|
      NotificationBuilder.new(
        notification_type: 'conversation_creation',
        user: user,
        account: account,
        primary_actor: conversation
      ).perform
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


