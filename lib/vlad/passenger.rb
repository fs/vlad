require 'vlad'

namespace :vlad do
  set :app_command, "/etc/init.d/httpd"

  remote_task :setup_app, :roles => :web do
    run %Q(sudo sh -c "ruby /etc/sliceconfig/install/interactive/passenger_config.rb '#{app_domain}' '#{application}' '#{environment}' '#{app_port}' '#{only_www}' > /etc/httpd/conf.d/vhosts/#{application}_#{environment}.conf")
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