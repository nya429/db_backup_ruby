#!/usr/bin/ruby
require 'json'

class DirBackup
  def initialize(parent_dir, target_dir)
    @parent_dir             = parent_dir
    @target_dir             = target_dir
    @app_type               = nil
    @backup_command         = nil
    @backup_exclude_options = ""
  end

  def full_dir_path
    @parent_dir + "/" + @target_dir
  end

  def detect_dir_type
    rails_command = "find #{self.full_dir_path} -maxdepth 3 -name Gemfile"
    drupal_command = "find #{self.full_dir_path} -maxdepth 3 -name *drupal*"
    phoenix_command = "find #{self.full_dir_path} -maxdepth 3 -name elixir*"
    if `#{rails_command}` != ""
      @app_type = "rails"
    elsif `#{drupal_command}` != ""
      @app_type = "drupal"
    elsif `#{phoenix_command}` != ""
      @app_type = "elixir"
    end
  end

  def abstract_backup
    case @app_type
    when "rails"
      @backup_command = ruby_backup_command
    when "drupal"
      @backup_command = drupal_backup_command
    when "elixir"
      @backup_command = elixir_backup_command
    else
      @backup_command = generic_backup_command
    end
  end

  def start_backup!
    self.detect_dir_type
    self.abstract_backup
    puts "#{Time.now} - Starting backup of #{@target_dir}"
    puts "> #{@backup_command}"
    `#{@backup_command}`
    exit_status = $?.exitstatus
    puts "#{Time.now} - Finished backup of #{@target_dir}"
    return exit_status
  end

  def ruby_backup_command
    if $options['backup_codebase'] == true
      old_release_array = `find #{self.full_dir_path}/releases/* -maxdepth 0 | sort -rn | tail -n +2`.split("\n")
      @backup_exclude_options = "--exclude='*shared/bundle*' --exclude='*/log' --exclude='*/releases/*/.git' "
      old_release_array.each do |release|
        @backup_exclude_options << " --exclude=#{release} "
      end
    else
      @backup_exclude_options = " --exclude='*/releases' "
    end

    generic_backup_command("rails")
  end

  ## placeholder until we determine minimal drupal backups
  def drupal_backup_command
    generic_backup_command("drupal")
  end

  ## placeholder until we determine minimal elixir backups
  def elixir_backup_command
    generic_backup_command("elixir")
  end

## backup everything in the dir
  def generic_backup_command(suffix = "dir")
    prefix = @parent_dir.gsub('/', '_')
    command = "cd #{@parent_dir} && tar " + @backup_exclude_options + " -zcvf /home/sara/backups/directories/#{$ts}/#{prefix}_#{@target_dir}_#{suffix}.tgz #{@target_dir}"
  end
end

puts "Starting apps backups at #{Time.now}"

Dir.chdir('/home/sara')

#note that optional_dirs expects the full path, not the parent path, as we expect these to be very custom
#we expect it to look like a hash, "app_path" = { child_dirs: true } if we want to iterate through the child dirs
$options = {'run_backups'      => false,
            'backup_retention' => 2,
            'backup_codebase'  => true,
            'optional_dirs'    => Hash.new,
          }

##if File.exists?('.sara_config.yml')
  #require 'yaml'
  #config = YAML.load_file('.sara_config.yml')
  #$options.merge!(config['apps']) if config['apps'].is_a? Hash
#end

#if $options['run_backups'] == true
  $ts = Time.now.strftime("%Y%m%d_%H%M%S")
  Dir.mkdir('backups') unless File.exists?('backups')
  Dir.mkdir('backups/directories') unless File.exists?('backups/directories')
  Dir.mkdir("backups/directories/#{$ts}") unless File.exists?("backups/directories/#{$ts}")

  counter = 0

  backup_dirs = { '/mnt/crypt'=>{child_dirs: false},
                  '/mnt/nocrypt'=>{child_dirs: false},
                  '/usr/local/apache2/www/drupal_apps'=>{child_dirs: true},
                  '/usr/local/apache2/www/rails_apps'=>{child_dirs: true},
                  '/var/www/apps'=>{child_dirs: true},
                }

  backup_dirs.merge!($options['optional_dirs'])

  results = {}

  backup_dirs.each do | dir, options |
    puts "Checking #{dir}..."
    if File.exists?(dir)
      puts "#{dir} exists..."
      if options[:child_dirs] == true
        Dir.entries(dir).reject { |entry| [ '.', '..' ].include?(entry) }.each do |child_dir|
          next if $options['ignore_staging'] && child_dir =~ /staging/
          backup = DirBackup.new(dir,child_dir)
          backup_exit_status = backup.start_backup!
          results["#{dir}/#{child_dir}"] = { backup_exit_status: backup_exit_status }
          counter += 1
          backup = nil
        end
      else
        last_slash_index = dir.rindex("/")
        # indices stuff to split out that last / into parent dir and backup dir
        # note that, if, for some reason, dir = "/"
        # parent_dir = "/", backup_dir = "", and tar will fail due to no target dir
        # ...I have no idea why dir might = "/", though.
        parent_dir = dir[0..last_slash_index-1]
        backup_dir = dir[last_slash_index+1..-1]

        backup = DirBackup.new(parent_dir, backup_dir)
        backup_exit_status = backup.start_backup!
        results["#{dir}"] = { backup_exit_status: backup_exit_status }
        counter += 1
        backup = nil
      end
    else
      puts "#{dir} does not exist, skipping..."
    end
  end

  puts "Created #{counter} application backup(s)"

  default_retention = $options['backup_retention']
  puts "Retention: #{default_retention}"
  `find ./backups/directories/ -type d -daystart -mtime +#{default_retention} -exec rm -r {} \\\;`
  cleanup_exit_status = $?.exitstatus
  results['cleanup_exit_status'] = cleanup_exit_status
  ## remove old strategy as well
  `find ./backups/apps/ -type d -daystart -mtime +#{default_retention} -exec rm -r {} \\\;`
#end

puts "Completed apps backups at #{Time.now}"
