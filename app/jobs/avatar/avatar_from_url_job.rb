class Avatar::AvatarFromUrlJob < ApplicationJob
  queue_as :purgable

  def perform(avatarable, avatar_url, preferred_filename = nil)
    return unless avatarable.respond_to?(:avatar)

    # Reuse an existing blob when a deterministic filename is supplied (eg: country flags)
    if preferred_filename.present?
      existing_blob = ActiveStorage::Blob.where(filename: preferred_filename)
                                         .where(content_type: ['image/png', 'image/jpeg', 'image/gif'])
                                         .order(created_at: :asc)
                                         .first
      if existing_blob
        begin
          # Attach and exit if the object exists on the storage service
          if existing_blob.service.exist?(existing_blob.key)
            avatarable.avatar.attach(existing_blob)
            return
          end
        rescue StandardError
          # If service existence check fails for any reason, fall back to attach
          avatarable.avatar.attach(existing_blob)
          return
        end
      end
    end

    avatar_file = Down.download(
      avatar_url,
      max_size: 15 * 1024 * 1024
    )
    if valid_image?(avatar_file)
      filename = preferred_filename.presence || avatar_file.original_filename
      avatarable.avatar.attach(io: avatar_file, filename: filename,
                               content_type: avatar_file.content_type)
    end
  rescue Down::NotFound, Down::Error => e
    Rails.logger.error "Exception: invalid avatar url #{avatar_url} : #{e.message}"
  end

  private

  def valid_image?(file)
    return false if file.original_filename.blank?

    # TODO: check if the file is an actual image

    true
  end
end
