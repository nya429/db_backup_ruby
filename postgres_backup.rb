#!/usr/bin/ruby
# TODO
# change folder from postgres to postgresql
require 'json'

postgres_version = `psql -V`.chomp

if postgres_version =~ /command not found/
  puts "Postgres is not installed on this server"
else
  puts "Starting postgres backups at #{Time.now}"

  Dir.chdir('/home/sara')

  options = {
    'skip_backups'       => false,
    'backup_retention'   => 14,
    'extra_dump_options' => [],
  }

  #if File.exists?('.sara_config.yml')
    #require 'yaml'
    #config = YAML.load_file('.sara_config.yml')
    #options.merge!(config['postgres']) if config['postgres'].is_a? Hash
  #end

  results = {}

  #unless File.exists?('.sara_skip_backups') || options['skip_backups'] == true
    ts = Time.now.strftime("%Y%m%d_%H%M%S")
    all_databases = `psql -U postgres -d postgres -t -A -c 'SELECT datname FROM pg_database'`.split("\n")
    databases_to_backup = all_databases - ['postgres', 'sara', 'template0', 'template1']

    extra_options = options['extra_dump_options'].join(" ")

    databases_to_backup.each do |database|
      `mkdir -p backups/postgres/#{ts}`

      `pg_dump -U postgres --clean --if-exists #{extra_options} #{database} > backups/postgres/#{ts}/#{database}.psql`
      dump_exit_status = $?.exitstatus

      puts `du -sh backups/postgres/#{ts}/#{database}.psql`

      `gzip backups/postgres/#{ts}/#{database}.psql`
      compression_exit_status = $?.exitstatus

      results[database] = { 
        dump_exit_status: dump_exit_status,
        compression_exit_status: compression_exit_status,
      }
    end

    default_retention = options['backup_retention']
    puts "Retention: #{default_retention}"

    `find ./backups/postgres/ -type d -daystart -mtime +#{default_retention} -exec rm -r {} \\\;`
    cleanup_exit_status = $?.exitstatus
    results['cleanup_exit_status'] = cleanup_exit_status

  puts "Completed postgres backups at #{Time.now}"
#end
