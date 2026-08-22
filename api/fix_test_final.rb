text = File.read('spec/requests/api/v1/vacancy_invitation_workflow_spec.rb')

text.gsub!(/\{ skill_id: 'java', skill_label: 'Java', expected_level: 3 \}/, "{ skill_id: 'java', skill_label: 'Java', expected_level: 3, l1_anchor: '1', l2_anchor: '2', l3_anchor: '3', l4_anchor: '4', l5_anchor: '5' }")
text.gsub!(/\{ skill_id: vacancy_skill\.skill_id, skill_label: vacancy_skill\.skill_label, expected_level: 4 \}/, "{ skill_id: vacancy_skill.skill_id, skill_label: vacancy_skill.skill_label, expected_level: 4, l1_anchor: '1', l2_anchor: '2', l3_anchor: '3', l4_anchor: '4', l5_anchor: '5' }")

text.gsub!("ActiveJob::Base.queue_adapter = :test", "require 'sidekiq/testing'\n        Sidekiq::Testing.inline!")

# Fix test 4 (Worker failed updates status, and retry works)
text.gsub!(/allow\(CandidateMailer\)\.to receive\(:with\)\.and_call_original/, "Sidekiq::Testing.inline!\n        allow(CandidateMailer).to receive(:with).and_call_original")

File.write('spec/requests/api/v1/vacancy_invitation_workflow_spec.rb', text)
