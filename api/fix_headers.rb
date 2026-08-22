lines = File.readlines('spec/requests/api/v1/vacancy_invitation_workflow_spec.rb')
lines.delete_at(6) # post ...
lines.delete_at(6) # token = ...
lines.delete_at(6) # { 'X-Tenant-Scheme' => ... }
lines.insert(6, "  token = JsonWebToken.encode(user_id: user.id, role: user.role, scheme: tenant.scheme)\n")
lines.insert(7, "  { 'X-Tenant-Scheme' => tenant.scheme, 'Content-Type' => 'application/json', 'Authorization' => \"Bearer \#{token}\" }\n")
File.write('spec/requests/api/v1/vacancy_invitation_workflow_spec.rb', lines.join)
