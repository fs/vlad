require 'vlad'

##
# used by update, out here so we can ensure all threads have the same value
def now
  @now ||= Time.now.utc.strftime("%Y%m%d%H%M.%S")
end

namespace :vlad do
  desc "Show the vlad setup.  This is all the default variables for vlad
    tasks.".cleanup

  task :debug do
    require 'yaml'

    # force them into values
    Rake::RemoteTask.env.keys.each do |key|
      next if key =~ /_release|releases|sudo_password/
      Rake::RemoteTask.fetch key
    end

    puts "# Environment:"
    puts
    y Rake::RemoteTask.env
    puts "# Roles:"
    y Rake::RemoteTask.roles
  end

  desc "Setup your servers. Before you can use any of the deployment
    tasks with your project, you will need to make sure all of your
    servers have been prepared with 'rake vlad:setup'. It is safe to
    run this task on servers that have already been set up; it will
    not destroy any deployed revisions or data.".cleanup

  task :setup do
    Rake::Task['vlad:setup_app'].invoke
  end

  def chown(path)
    "#{sudo_cmd} chown -R #{app_user}:#{app_group} #{path}/"
  end

  desc "Prepares application servers for deployment.".cleanup

  remote_task :setup_app, :roles => :app do
    dirs = [deploy_to, releases_path, scm_path, shared_path]
    dirs += %w(system log pids).map { |d| File.join(shared_path, d) }
    run [ "umask #{umask}",
          "mkdir -p #{dirs.join(' ')}",
          chown(shared_path)
        ].join(" && ")
  end

  desc "Updates your application server to the latest revision.  Syncs
    a copy of the repository, exports it as the latest release, fixes
    up your symlinks, symlinks the latest revision to current and logs
    the update.".cleanup

  remote_task :update, :roles => :app do
    symlink = false
    begin
      run [ "cd #{scm_path}",
            "#{source.checkout revision, '.'}",
            "#{source.export ".", release_path}",
            "chmod -R g+w #{latest_release}",
            chown(latest_release),
            "rm -rf #{latest_release}/log #{latest_release}/public/system #{latest_release}/tmp/pids",
            "mkdir -p #{latest_release}/db #{latest_release}/tmp",
            "ln -s #{shared_path}/log #{latest_release}/log",
            "ln -s #{shared_path}/system #{latest_release}/public/system",
            "ln -s #{shared_path}/pids #{latest_release}/tmp/pids"
          ].join(" && ")

      run  "if [ -f #{current_release}/config/cron/#{environment}.cron ]
            then
            sudo cp -f #{current_release}/config/cron/#{environment}.cron /etc/cron.d/#{application}_#{environment}.cron
            fi"

      symlink = true
      run "rm -f #{current_path} && ln -s #{latest_release} #{current_path}"

      run "echo #{now} $USER #{revision} #{File.basename release_path} >> #{deploy_to}/revisions.log"
    rescue => e
      run "rm -f #{current_path} && ln -s #{previous_release} #{current_path}" if
        symlink
      run "rm -rf #{release_path}"
      raise e
    end
  end

  desc "Updates current release.".cleanup

  remote_task :hot_update, :roles => :app do
    run [ "cd #{current_path}",
          source.update(revision),
          chown(current_path),
          "sudo -u #{app_user} rm -rf #{current_release}/public/javascripts/cached #{current_release}/public/stylesheets/cached"
        ].join(" && ")

    run  "if [ -f #{current_release}/config/cron/#{environment}.cron ]
          then
          sudo cp -f #{current_release}/config/cron/#{environment}.cron /etc/cron.d/#{application}_#{environment}.cron
          fi"
  end

  desc "Fixes permissions on the latest release and shared directory".cleanup
  
  remote_task :fix_permissions, :roles => :app do
    run [ chown(current_path),
          chown(shared_path)
        ].join(" && ")
  end

  desc "Run the migrate rake task for the the app. By default this is run in
    the latest app directory.  You can run migrations for the current app
    directory by setting :migrate_target to :current.  Additional environment
    variables can be passed to rake via the migrate_env variable.".cleanup

  # No application files are on the DB machine, also migrations should only be
  # run once.
  remote_task :migrate, :roles => :app do
    break unless target_host == Rake::RemoteTask.hosts_for(:app).first

    directory = case migrate_target.to_sym
                when :current then current_path
                when :latest  then current_release
                else raise ArgumentError, "unknown migration target #{migrate_target.inspect}"
                end

    run "cd #{current_path}; #{rake_cmd} RAILS_ENV=#{environment} db:migrate #{migrate_args}"
  end

  desc "Invoke a single command on every remote server. This is useful for
    performing one-off commands that may not require a full task to be written
    for them.  Simply specify the command to execute via the COMMAND
    environment variable.  To execute the command only on certain roles,
    specify the ROLES environment variable as a comma-delimited list of role
    names.

      $ rake vlad:invoke COMMAND='uptime'".cleanup

  remote_task :invoke do
    command = ENV["COMMAND"]
    abort "Please specify a command to execute on the remote servers (via the COMMAND environment variable)" unless command
    puts run(command)
  end

  desc "Copy arbitrary files to the currently deployed version using
    FILES=a,b,c. This is useful for updating files piecemeal when you
    need to quickly deploy only a single file.

    To use this task, specify the files and directories you want to copy as a
    comma-delimited list in the FILES environment variable. All directories
    will be processed recursively, with all files being pushed to the
    deployment servers. Any file or directory starting with a '.' character
    will be ignored.

      $ rake vlad:upload FILES=templates,controller.rb".cleanup

  remote_task :upload do
    file_list = (ENV["FILES"] || "").split(",")

    files = file_list.map do |f|
      f = f.strip
      File.directory?(f) ? Dir["#{f}/**/*"] : f
    end.flatten

    files = files.reject { |f| File.directory?(f) || File.basename(f)[0] == ?. }

    abort "Please specify at least one file to update (via the FILES environment variable)" if files.empty?

    files.each do |file|
      rsync file, File.join(current_path, file)
    end
  end

  desc "Rolls back to a previous version and restarts. This is handy if you
    ever discover that you've deployed a lemon; 'rake vlad:rollback' and
    you're right back where you were, on the previously deployed
    version.".cleanup

  remote_task :rollback do
    if releases.length < 2 then
      abort "could not rollback the code because there is no prior release"
    else
      run "rm #{current_path}; ln -s #{previous_release} #{current_path} && rm -rf #{current_release}"
    end

    Rake::Task['vlad:start'].invoke
  end

  desc "Clean up old releases. By default, the last 5 releases are kept on
    each server (though you can change this with the keep_releases variable).
    All other deployed revisions are removed from the servers.".cleanup

  remote_task :cleanup do
    max = keep_releases
    if releases.length <= max then
      puts "no old releases to clean up #{releases.length} <= #{max}"
    else
      puts "keeping #{max} of #{releases.length} deployed releases"

      directories = (releases - releases.last(max)).map { |release|
        File.join(releases_path, release)
      }.join(" ")

      run "rm -rf #{directories}"
    end
  end

end # namespace vlad
