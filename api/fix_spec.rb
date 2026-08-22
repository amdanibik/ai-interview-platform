text = File.read('spec/requests/api/v1/vacancy_invitation_workflow_spec.rb')

text.gsub!(/let\(:user\)\s*\{\s*create\(:user\)\s*\}/, "let(:user) { create(:user, :admin, password: 'secure_password123') }")
text.gsub!(/let\(:tenant\)\s*\{\s*user\.tenant\s*\}/, "let(:tenant) { Organization.first || Organization.create!(identifier: 'test', name: 'Test', scheme: 'test', host: 'test.com') }")
text.gsub!(/let\(:base_headers\)\s*\{\s*auth_headers_for\(user\)\s*\}/, <<~RUBY.strip)
  let(:base_headers) do
    post '/api/v1/auth/login', params: { email: user.email, password: 'secure_password123' }, as: :json
    token = JSON.parse(response.body)['token']
    { 'X-Tenant-Scheme' => tenant.scheme, 'Content-Type' => 'application/json', 'Authorization' => "Bearer \#{token}" }
  end
RUBY

text.gsub!(/let\(:vacancy\)\s*\{\s*create\(:vacancy.*?\}\s*/m, "let(:vacancy) { Vacancy.create!(role_title: 'Backend Dev', tenant_id: tenant.id, created_by: user.id) }\n")
text.gsub!(/let!\(:vacancy_skill\)\s*\{\s*create\(:vacancy_skill, vacancy: vacancy.*?\}\s*/m, "let!(:vacancy_skill) { VacancySkill.create!(vacancy_id: vacancy.id, skill_id: 'ruby', skill_label: 'Ruby', expected_level: 4) }\n")

text.gsub!(/let\(:assessment\)\s*\{\s*create\(:assessment, tenant: tenant\)\s*\}/, "let(:assessment) { create(:assessment, tenant_id: tenant.id) }")

text.gsub!(/let\(:session\)\s*\{\s*create\(:session, assessment: assessment, candidate_email: '(.*?)', invitation_status: '(.*?)'\)\s*\}/, "let(:session) { create(:session, assessment: assessment, tenant_id: tenant.id, candidate_email: '\\1', invitation_status: '\\2') }")

# Change all `params: { ... }` to `params: { ... }, as: :json` safely.
text.gsub!(/params:\s*\{\s*assessment:\s*attributes\s*\}/, "params: { assessment: attributes }, as: :json")
text.gsub!(/params:\s*\{\s*session:\s*\{\s*candidate_name(.*?)\}\s*\}/, "params: { session: { candidate_name\\1} }, as: :json")

File.write('spec/requests/api/v1/vacancy_invitation_workflow_spec.rb', text)
