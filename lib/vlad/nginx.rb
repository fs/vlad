require 'vlad'

namespace :vlad do
  set :web_command, "/etc/init.d/nginx"

  remote_task :setup_app, :roles => :web do
    run %Q(sudo sh -c "ruby /etc/sliceconfig/install/interactive/nginx_config.rb '#{app_domain}' '#{application}' '#{environment}' '#{app_port}' '#{app_servers}' '#{only_www}' > /etc/nginx/vhosts/#{application}_#{environment}.conf")
  end
  
  desc '(Re)Start the web servers'
  remote_task :start_web, :roles => :web do
    run %Q(sudo #{web_command} configtest && sudo #{web_command} reload)
  end
end