class NotificationBuilder
  pattr_initialize [:notification_type!, :user!, :account!, :primary_actor!, :secondary_actor]

  def perform
    build_notification
  end

  private

  def current_user
    Current.user
  end

  def user_subscribed_to_notification?
    notification_setting = user.notification_settings.find_by(account_id: account.id)
    # added for the case where an assignee might be removed from the account but remains in conversation
    return false if notification_setting.blank?

    return true if notification_setting.public_send("email_#{notification_type}?")
    return true if notification_setting.public_send("push_#{notification_type}?")

    false
  end

  def build_notification
    # Create conversation_creation notification only if user is subscribed to it
    return if notification_type == 'conversation_creation' && !user_subscribed_to_notification?
    # skip notifications for blocked conversations except for user mentions
    return if primary_actor.contact.blocked? && notification_type != 'conversation_mention'

    # Throttle conversation_creation notifications briefly to avoid duplicates from multiple listeners
    if notification_type == 'conversation_creation'
      lock_key = "lock:notification:creation:acct:#{account.id}:user:#{user.id}:conv:#{primary_actor.class}:#{primary_actor.id}"
      lock_manager = Redis::LockManager.new
      # If we cannot acquire a short-lived lock, skip creating a duplicate notification
      return unless lock_manager.lock(lock_key, Redis::LockManager::LOCK_TIMEOUT)
      # No need to explicitly unlock; the lock expires quickly
    end

    user.notifications.create!(
      notification_type: notification_type,
      account: account,
      primary_actor: primary_actor,
      # secondary_actor is secondary_actor if present, else current_user
      secondary_actor: secondary_actor || current_user
    )
  end
end
