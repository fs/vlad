require 'vlad'

namespace :vlad do
  set :app_command, "/etc/init.d/httpd"

  remote_task :setup_app, :roles => :web do
    config_file = "/etc/httpd/conf.d/vhosts/#{application}_#{environment}.conf"
    run %Q(sudo test -e #{config_file} || sudo sh -c "ruby /etc/sliceconfig/install/interactive/passenger_config.rb '#{app_domain}' '#{application}' '#{environment}' '#{app_port}' #{only_www ? 1 : 0} > #{config_file}")
  end

  desc 'Restart Passenger'
  remote_task :start_app, :roles => :app do
    run "touch #{current_release}/tmp/restart.txt"
  end
  
  desc 'Restarts the apache servers'
  remote_task :start_web, :roles => :app do
    run "sudo #{app_command} configtest && sudo #{app_command} graceful"
  end
end