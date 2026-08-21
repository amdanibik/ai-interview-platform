# frozen_string_literal: true

class InvitationSenderWorker
  include Sidekiq::Worker

  sidekiq_options queue: :mailers, retry: 3

  sidekiq_retries_exhausted do |msg, _ex|
    session_id = msg['args'].first
    session = Session.find_by(id: session_id)
    session&.update(
      invitation_status: 'failed',
      invitation_error:  "Failed after #{msg['retry_count']} retries: #{msg['error_message']}"
    )
  end

  def perform(session_id)
    session = Session.find(session_id)
    
    CandidateMailer.with(session: session).invitation_email.deliver_now
    
    session.update!(
      invitation_status: 'sent',
      invitation_sent_at: Time.current,
      invitation_error: nil
    )
  rescue => e
    session.update(invitation_status: 'failed', invitation_error: e.message)
    raise e
  end
end
