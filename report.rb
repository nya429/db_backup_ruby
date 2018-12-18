require 'rubygems' # need this in case of ruby 1.8.7 where json is a gem
require 'json'

report_type = ARGV[0]
report_types = %w(daily heartbeat test)
report_type = 'unknown' unless report_types.include? report_type

unless report_type == 'test'
  puts
  puts '~start'
  puts Time.now.to_s
end

def application_directories(options = {})
  dirs_with_apps = %w(
    /var/www/apps/*
    /usr/local/apache2/www/rails_apps/*
    /usr/local/apache2/www/drupal_apps/*
  )

  app_dirs =
    if options[:full_path]
       `find #{dirs_with_apps.join(' ')} -maxdepth 0 -type d`
    else
       `find #{dirs_with_apps.join(' ')} -maxdepth 0 -type d -printf "%f\n"`
    end

  app_dirs.split
end

def create_app_info_hashes
  app_dirs = application_directories(full_path: true)
  return [] if app_dirs.empty?
  # initialize hash for info about each app
  app_info_hashes = []
  app_dirs.each do |full_app_path|
    app_dir = full_app_path.split("/").last
    rails_command = "find #{full_app_path} -maxdepth 3 -name Gemfile"
    drupal_command = "find #{full_app_path} -maxdepth 3 -name *drupal*"
    phoenix_command = "find #{full_app_path} -maxdepth 3 -name elixir*"

    if `#{rails_command}` != ""
      gems = `find -L #{full_app_path}/current -maxdepth 1 -name Gemfile.lock -exec cat {} \\;`.split("\n")
      rails_gem = gems.select { |ruby_gem| ruby_gem[/^\s*rails \(\d\.\d\.\d\)/] }.first

      language = 'ruby'
      language_version = `find -L #{full_app_path}/current -maxdepth 1 -name .ruby-version -exec cat {} \\;`.chomp
      framework = 'rails'
      framework_version = rails_gem && rails_gem[/\d\.\d\.\d/]
      git_revision = `cat #{full_app_path}/current/REVISION`.chomp

    elsif `#{drupal_command}` != ""
      drupal_changelog = `head -3 #{full_app_path}/CHANGELOG.txt`

      language = 'php'
      language_version = `php -v`.match(/PHP (\d\.\d*\.*\d*)/).captures.first
      framework = 'drupal'
      framework_version = if drupal_changelog != ""
        drupal_changelog.match(/Drupal (\d\.\d*\.*\d*)/).captures.first
      end
      git_revision = nil

    elsif `#{phoenix_command}` != ""
      elixir_version_file = `find -L #{full_app_path}/lib -maxdepth 1 -name 'elixir-*'`
      phoenix_version_file = `find -L #{full_app_path}/lib -maxdepth 1 -name 'phoenix-*'`

      language = 'elixir'
      language_version = elixir_version_file && elixir_version_file.match(/elixir-(\d\.\d\.\d)/).captures.first
      framework = 'phoenix'
      framework_version = phoenix_version_file && phoenix_version_file.match(/phoenix-(\d\.\d\.\d)/).captures.first
      git_revision = nil

    else
      language = nil
      language_version = nil
      framework = nil
      framework_version = nil
      git_revision = nil
    end

    application_guid = `cat #{full_app_path}/.application_guid`.chomp

    app_info_hashes << {
      application_guid: application_guid,
      path: full_app_path,
      directory: app_dir,
      git_revision: git_revision,
      language: language,
      language_version: language_version,
      framework: framework,
      framework_version: framework_version,
      app_packages: create_app_packages(framework, full_app_path, language_version),
    }
  end

  app_info_hashes
end

def create_app_packages(framework, full_app_path, language_version)
  app_packages = []

  case framework
  when 'rails'
    if language_version
      bundler_version = `cd #{full_app_path}/current/ && RBENV_VERSION=#{language_version} bundle version`.match(/(\d\.\d*\.*\d*)/)
    else
      bundler_version = `cd #{full_app_path}/current/ && bundle version`.match(/(\d\.\d*\.*\d*)/)
    end
    bundler_version = bundler_version && bundler_version.captures.first

    app_packages << {
      package_name: 'bundler',
      package_version: bundler_version
    }
  when 'drupal'
  when 'elixir'
  end

  app_packages
end


hostname = `hostname`.chomp
datacenter = 'unknown'
map = {
  'annlnx'                       => 'online_tech',
  'annlnx\d+in'                  => 'online_tech_indy',
  'BillingApp'                   => 'tempus',
  'BillingPro'                   => 'tempus',
  'cpm.local'                    => 'tempus',
  'CPM.LOCAL'                    => 'tempus',
  'CPAFC'                        => 'tempus',
  'fortcom'                      => 'online_tech',
  'lifeworks'                    => 'lifeworks',
  'localhost.localdomain'        => 'mrci',
  'mrci.local'                   => 'mrci',
  'NEA-S-DATA'                   => 'nearc',
  'srvmed'                       => 'cca',
  'testbed'                      => 'tempus',
  'uds'                          => 'uds',
  'commonwealthcare'             => 'cca',
  'NEARC'                        => 'nearc',
}
map.each { |k,v| datacenter = v if hostname =~ /#{k}/i }

## GUID
# create a Globally Unique Identifier (GUID) unless one exists
unless File.exists?('.server_guid')
  require 'securerandom'
  guid = SecureRandom.uuid
  File.open(".server_guid", "w") { |file| file.write(guid) }
end
# get the servers GUID
server_guid = `cat .server_guid`.chomp

commands = [ ]
results = [ ]

# will always run
if %w(unknown heartbeat daily test).include? report_type
  ## Core info
  commands << 'df -P'   # disk space (processed by Partition)
  commands << 'vmstat'  # memory stats
  commands << 'free -m' # memory stats
  commands << %q(awk '( $1 == "MemTotal:" ) { print $2/1048576 }' /proc/meminfo) # total memory
  commands << %q(cat /proc/cpuinfo | grep -o processor | wc -l) # number of cpu cores
  commands << 'iostat'  # cpu avg utilization & device access state
  commands << 'ifconfig' # network interfaces (older OS)
  commands << 'ip addr' # network interfaces (newer OS)
  commands << 'curl https://wtfismyip.com/text'  # external ip address
  commands << 'ps -Af'  # processes
  commands << 'uptime'  # server uptime
  commands << 'date +"%Y-%m-%d %H:%M:%S" -d @$(( $(date +%s) - $(cut -f1 -d. /proc/uptime) ))'  # last reboot datetime
  commands << 'cat /etc/redhat-release'  # linux version (redhat)
  commands << 'cat /etc/lsb-release'  # linux version (ubuntu)
  commands << 'cat /etc/issue'  # linux version (other)
  commands << 'uname -a'  # kernel version

  ## Applications
  # app directories
  results << { :command => "application_directories", :result => application_directories, :error => nil }
  results << { :command => "app_info_hashes", :result => create_app_info_hashes, :error => nil }
  commands << 'ls -l /usr/local/apache2/www/rails_apps/'
  commands << 'ls -l /usr/local/apache2/www/drupal_apps/'
  commands << 'ls -l /var/www/apps/'
  # vhost directories
  commands << 'ls -l /usr/local/apache2/conf/extra/'
  commands << 'ls -l /usr/local/apache2/conf/rails_apps/'
  commands << 'ls -l /usr/local/apache2/conf/drupal_apps/'
  # apache virtual hosts
  commands << 'apachectl -S' # list current virtual hosts in use
  commands << 'apache2ctl -S' # list current virtual hosts in use

  ## Backups
  commands << 'find -L backups'
  commands << "find -L backups -name '*.tgz' -exec ls -s {} \\;"
  commands << "find -L backups -name '*.sql.gz' -exec ls -s {} \\;"
  commands << "find -L backups -name '*.psql.gz' -exec ls -s {} \\;"

end

# will only run once, daily
if %w(unknown daily test).include? report_type
  ## Databases
  # MySQL
  # List of databases
  commands << "mysql INFORMATION_SCHEMA -N -s -e \"select distinct table_schema from TABLES WHERE table_schema NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys')\""
  # Contents of my.cnf
  commands << "cat /etc/my.cnf"
  # MySQL configuration info
  commands << "if [ -d /etc/my.cnf.d ]; then if [ -f /etc/my.cnf.d/* ]; then cat /etc/my.cnf | cat - /etc/my.cnf.d/*; fi; else cat /etc/my.cnf; fi"
  # MySQL InnoDB memory info
  commands << "mysql -N -s -e \"SELECT CEILING(Total_InnoDB_Bytes*1.6/POWER(1024,3)) RIBPS FROM (SELECT SUM(data_length+index_length) Total_InnoDB_Bytes FROM information_schema.tables WHERE engine='InnoDB') A;\""
  # Filter for MySQL tables for which character set or collation settings are wrong
  commands << "mysql -N -s -e \"SELECT table_schema, table_name, character_set_name, collation_name FROM information_schema.columns WHERE ((character_set_name IS NOT NULL AND character_set_name <> 'utf8') OR (collation_name IS NOT NULL AND collation_name <> 'utf8_unicode_ci')) GROUP BY table_name AND table_schema NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys');\""
  # Filter for MySQL tables for which engine is wrong
  commands << "mysql -N -s -e \"SELECT table_schema, table_name, engine FROM information_schema.tables WHERE (engine IS NOT NULL and engine <> 'InnoDB') AND table_schema NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys');\""

  #PostgreSQL
  # List of databases
  commands << "psql -U postgres -q -A -t -c \"SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN ('postgres')\""

  ## Aggregate Backup Size
  commands << 'du -h backups'

  ## Utilities
  commands << 'yum makecache fast'
  commands << 'yum list installed --debuglevel=0'
  commands << 'yum check-update --debuglevel=0'
  commands << "/usr/lib/update-notifier/apt-check -p 2>&1"
  commands << 'dpkg --get-selections | grep -v deinstall'
  commands << 'git --version'
  commands << 'ruby -v'
  commands << 'rbenv versions'
  commands << 'gem list'
  commands << 'cat /etc/redhat-release'
  commands << 'mysql -V'
  commands << 'openssl version'
  commands << 'apachectl -v'
  commands << 'apache2ctl -v'
  commands << 'psql --version'
  commands << "passenger --version |  grep '[0-9]'"
  # sudo passenger-memory-stats
  # sudo (logrotate config)
  # sudo (time server configuration)

  ## User environments
  # users.each do |u|
  #  commands << "sudo ls -la /home/#{user}"
  #  commands << "sudo more /var/spool/cron/#{user}"
  #  commands << 'rbenv versions'
  #  commands << 'ps x'
  # end


  # Permissions
  commands << 'chmod 600 .password'
  commands << 'chmod 600 .my.cnf'

  # Cleanup
  commands << 'rm ~/.bash_history'
  commands << 'rm ~/.mysql_history'
end

commands.each do |command|
  h = { :command => command, :result => nil, :error => nil }
  begin
    h[:result] = `#{command}`
  rescue Exception => e
    h[:error] = e.to_json
  end
  results << h
end

report_hash = {
  :server_guid => server_guid,
  :datacenter_name => datacenter,
  :hostname => hostname,
  :report_type => report_type,
  :data => results.to_json
}

