class VisitorListener < BaseListener
  # Triggered when the widget is loaded on a page
  # Event payload comes from Api::V1::Widget::EventsController#create
  # with event name 'webwidget.loaded'
  def webwidget_loaded(event)
    contact_inbox = event.data[:contact_inbox]
    return if contact_inbox.blank?

    account = contact_inbox.inbox.account
    initial_path = extract_navigation_path(event)
    # Ensure there is a conversation so that the notification can deep-link
    conversation = contact_inbox.conversations.last
    if conversation.blank?
      # Add a short idempotency lock to avoid double-create in burst loads
      lock_key = "lock:visitor_conv:create:ci:#{contact_inbox.id}"
      lock = Redis::LockManager.new
      if lock.lock(lock_key, 1.second)
        conversation = Conversation.create!(
          account_id: account.id,
          inbox_id: contact_inbox.inbox_id,
          contact_id: contact_inbox.contact_id,
          contact_inbox_id: contact_inbox.id,
          additional_attributes: build_additional_attributes(event),
          status: :pending
        )
        # Create a lightweight private incoming message so clients have a sender context
        # This will be hidden from widget (private) but available for agent/mobile rendering
        conversation.messages.create!(
          account_id: account.id,
          inbox_id: contact_inbox.inbox_id,
          sender: contact_inbox.contact,
          message_type: :incoming,
          content: '',
          private: true,
          additional_attributes: { 'system' => true }
        )
      else
        # Another process created it; fetch latest
        conversation = contact_inbox.conversations.last
      end
    end

    # Mark as visitor-loaded and persist best-effort location for reliability
    country_code = fetch_country_code(contact_inbox.contact)
    add_visitor_marker(conversation, country_code, initial_path)
    persist_country_if_missing(contact_inbox.contact, country_code)
    attach_country_flag_avatar(contact_inbox.contact, country_code)
    notify_all_agents(conversation.inbox.account, conversation)
  end

  def visitor_navigated(event)
    contact_inbox = event.data[:contact_inbox]
    return if contact_inbox.blank?

    conversation = contact_inbox.conversations.last
    return if conversation.blank?

    path = extract_navigation_path(event)
    return if path.blank?
    return if duplicate_navigation_event?(conversation, path)

    store_initial_path(conversation, path)
    message_params = navigation_activity_message_params(conversation, path)
    Conversations::ActivityMessageJob.perform_later(conversation, message_params)
  end


  # Intentionally do not handle webwidget.triggered to avoid click-based notifications

  private

  def extract_navigation_path(event)
    info = (event.data[:event_info] || {}).with_indifferent_access
    referer = info[:referer]
    return if referer.blank?

    NavigationPathHelper.sanitized_path(referer)
  end

  def duplicate_navigation_event?(conversation, path)
    conversation.messages.where(message_type: :activity, private: true)
                 .where("content_attributes ->> 'activity_identifier' = ?", 'visitor_navigated')
                 .order(created_at: :desc)
                 .limit(1)
                 .pluck(Arel.sql("content_attributes ->> 'path'"))
                 .first == path
  end

  def navigation_activity_message_params(conversation, path)
    {
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :activity,
      content: I18n.t('conversations.activity.visitor.navigated', path: path),
      private: true,
      content_attributes: {
        'activity_identifier' => 'visitor_navigated',
        'path' => path
      }
    }
  end

  def build_additional_attributes(event)
    info = event.data[:event_info] || {}
    {
      'browser_language' => info[:browser_language],
      'widget_language' => info[:widget_language],
      'browser' => info[:browser],
      'referer' => info[:referer]
    }.compact
  end

  def add_visitor_marker(conversation, country_code, initial_path)
    attrs = conversation.additional_attributes || {}
    attrs['visitor_loaded'] = true
    attrs['visitor_country_code'] = country_code if country_code.present?
    attrs['visitor_initial_path'] ||= initial_path if initial_path.present?
    # rubocop:disable Rails/SkipsModelValidations
    conversation.update_column(:additional_attributes, attrs)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def store_initial_path(conversation, path)
    return if path.blank?

    attrs = conversation.additional_attributes || {}
    return if attrs['visitor_initial_path'].present?

    attrs['visitor_initial_path'] = path
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
    # Only override when the contact is using the default placeholder (no avatar attached)
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

