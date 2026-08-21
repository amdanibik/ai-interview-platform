require 'rails_helper'

RSpec.describe 'Vacancy & Invitation Workflow', type: :request do
  let(:user) { create(:user) }
  let(:tenant) { user.tenant }
  let(:base_headers) { auth_headers_for(user) }

  describe 'Vacancy to Assessment connection' do
    let(:vacancy) { create(:vacancy, role_title: 'Backend Dev', tenant: tenant) }
    let!(:vacancy_skill) { create(:vacancy_skill, vacancy: vacancy, skill_id: 'ruby', skill_label: 'Ruby', expected_level: 4) }

    it '1. Existing assessment without vacancy remains valid (can be created)' do
      attributes = {
        name: 'Standalone Role', time_limit_min: 45, language: 'en',
        assessment_skills_attributes: [{ skill_id: 'java', skill_label: 'Java', expected_level: 3 }]
      }
      post '/api/v1/assessments', headers: base_headers, params: { assessment: attributes }
      expect(response).to have_http_status(:created)
      expect(Assessment.last.vacancy_id).to be_nil
    end

    it '10, 11, 12. Vacancy can create an assessment and prefill assessment skills' do
      attributes = {
        name: vacancy.role_title,
        vacancy_id: vacancy.id,
        time_limit_min: 30,
        language: 'en',
        assessment_skills_attributes: [
          { skill_id: vacancy_skill.skill_id, skill_label: vacancy_skill.skill_label, expected_level: 4 }
        ]
      }
      post '/api/v1/assessments', headers: base_headers, params: { assessment: attributes }
      
      expect(response).to have_http_status(:created)
      assessment = Assessment.last
      expect(assessment.vacancy_id).to eq(vacancy.id)
      expect(assessment.assessment_skills.first.skill_id).to eq('ruby')
    end
  end

  describe 'Email Invitation Workflow' do
    let(:assessment) { create(:assessment, tenant: tenant) }

    it '2, 4. Session can store candidate email and starts with pending invitation' do
      post "/api/v1/assessments/#{assessment.id}/sessions", 
           headers: base_headers, 
           params: { session: { candidate_name: 'Bob', candidate_email: 'bob@example.com' } }
           
      expect(response).to have_http_status(:created)
      session = Session.last
      expect(session.candidate_email).to eq('bob@example.com')
      expect(session.invitation_status).to eq('pending')
    end

    it '3. Invalid email is rejected' do
      post "/api/v1/assessments/#{assessment.id}/sessions", 
           headers: base_headers, 
           params: { session: { candidate_name: 'Bob', candidate_email: 'not-an-email' } }
           
      expect(response).to have_http_status(:unprocessable_entity)
    end

    context 'sending limits and state transitions' do
      let(:session) { create(:session, assessment: assessment, candidate_email: 'alice@example.com', invitation_status: 'pending') }

      it '5, 6, 9. Invitation can be sent, changes status, and duplicate send prevented' do
        ActiveJob::Base.queue_adapter = :test
        
        post "/api/v1/sessions/#{session.id}/invitation", headers: base_headers
        expect(response).to have_http_status(:success)
        expect(session.reload.invitation_status).to eq('sent')
        
        # 9. Duplicate prevent
        post "/api/v1/sessions/#{session.id}/invitation", headers: base_headers
        expect(response).to have_http_status(:unprocessable_entity)
        expect(JSON.parse(response.body)['errors'][0]['message']).to eq('Invitation already sent')
      end
    end
    
    context 'Sidkiq Worker Failure handling' do
      let(:session) { create(:session, assessment: assessment, candidate_email: 'alice@test.example', invitation_status: 'pending') }
      
      it '7, 8. Worker failed updates status, and retry works' do
        allow(CandidateMailer).to receive(:with).and_raise(StandardError.new("SMTP Down"))
        
        expect {
          InvitationSenderWorker.new.perform(session.id)
        }.to raise_error("SMTP Down")
        
        # 7. Failed status updated
        expect(session.reload.invitation_status).to eq('failed')
        expect(session.invitation_error).to eq("SMTP Down")
        
        # 8. Retry works through controller point (failed allows retry)
        allow(CandidateMailer).to receive(:with).and_call_original
        post "/api/v1/sessions/#{session.id}/invitation", headers: base_headers
        expect(response).to have_http_status(:success)
        expect(session.reload.invitation_status).to eq('sent')
      end
    end
  end
end
