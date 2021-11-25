# create a Aeon Client user
if AppConfig.has_key?(:aeon_client_username)
  DB.open do
    ArchivesSpaceService.create_hidden_system_user(AppConfig[:aeon_client_username], "Aeon Client", AppConfig[:aeon_client_password])
    DBAuth.set_password(AppConfig[:aeon_client_username], AppConfig[:aeon_client_password])

    unless ArchivesSpaceService.create_group('AeonClientAccess', "Aeon Client", [AppConfig[:aeon_client_username]], ["view_repository", "view_all_records"])
      # group already exists so just add member
      RequestContext.open(:repo_id => Repository.global_repo_id) do
        group = Group[:group_code => 'AeonClientAccess']
        group.remove_all_user
        group.add_user(User[:username => AppConfig[:aeon_client_username]])
      end
    end
  end
end