#!/usr/bin/ruby
require 'fileutils'
require 'json'

puts "Starting mysql backups at #{Time.now}"
## Dir.chdir('/home/annadmin')
Dir.chdir('/home/ysong')

options = {
  'skip_backups'         => false,
  # 'backup_retention'     => 4,
  'backup_retention'     => 2,
  # applications can be processing as dumps are happening,
  # some processing creates tables on the fly and drops them after
  # processing is completed.  This ignores those errors
  'ignore_create_errors' => false,
  'extra_dump_options' => [],
}

##if File.exists?('.sara_config.yml')
  #require 'yaml'
  #config = YAML.load_file('.sara_config.yml')
  #options.merge!(config['mysql']) if config['mysql'].is_a? Hash
#end

results = {}

#unless File.exists?('.sara_skip_backups') || options['skip_backups'] == true
  excluded_databases = [ 'Database', 'mysql', 'information_schema', 'performance_schema', 'sys' ]
  ts = Time.now.strftime("%Y%m%d_%H%M%S")

  `mysql -e "show databases"`.split("\n").each do |database|
    next if excluded_databases.include?(database)
    next if options['ignore_staging'] && database =~ /staging/

    # create backup folder for todays backups if not already created

    ## FIXME FileUtils.mkdir_p "/u01/backups/mysql/#{ts}"
    FileUtils.mkdir_p "backups/mysql/#{ts}"

    ignore_create_errors = options['ignore_create_errors'] ? '--ignore-create-error' : ''
    extra_options        = options['extra_dump_options'].join(" ")

    puts "#{Time.now}: dumping #{database}"
    ## FIXME `mysqldump --single-transaction --hex-blob #{ignore_create_errors} #{extra_options} #{database} > /u01/backups/mysql/#{ts}/#{database}.sql`
    `mysqldump --single-transaction --hex-blob #{ignore_create_errors} #{extra_options} #{database} > backups/mysql/#{ts}/#{database}.sql`
    dump_exit_status = $?.exitstatus

    puts "#{Time.now}: logging uncompressed mysqldump size"
    ##  FIXME uncompressed_size = `ls -l /u01/backups/mysql/#{ts}/#{database}.sql | awk '{print $5}'`
    uncompressed_size = `ls -l backups/mysql/#{ts}/#{database}.sql | awk '{print $5}'`
    puts "#{database}.sql => #{uncompressed_size}"

    puts "#{Time.now}: zipping #{database}.sql"
    ## FIXME `gzip /u01/backups/mysql/#{ts}/#{database}.sql`
    `gzip backups/mysql/#{ts}/#{database}.sql`
    compression_exit_status = $?.exitstatus

    results[database] = { 
      dump_exit_status: dump_exit_status,
      compression_exit_status: compression_exit_status,
    }
  end

  default_retention = options['backup_retention']

  puts "Retention: #{default_retention}"
  ## FIXME `find /u01/backups/mysql/ -type d -daystart -mtime +#{default_retention} -exec rm -r {} \\\;`
  `find ./backups/mysql/ -type d -daystart -mtime +#{default_retention} -exec rm -r {} \\\;`
  cleanup_exit_status = $?.exitstatus
  results['cleanup_exit_status'] = cleanup_exit_status
#end

puts "Completed mysql backups at #{Time.now}"
