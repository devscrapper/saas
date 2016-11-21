#---------------------------------------------------------------------------------------------------------------------
# deploy avec capistrano V3
#---------------------------------------------------------------------------------------------------------------------
#
# first deploy :
# -------------
# install rvm :
# install ruby :
# Next deploy :
# -------------
# avant tout deploy, il faut publier sur https://devscrapper/enginebot.git avec la commande
# git push origin master
#
# pour deployer dans un terminal avec ruby 223 dans la path : cap production deploy
# cette commande prend en charge :
# la publication des sources vers le serveur cible
# la publication des fichiers de paramèrage :
# les liens vers les repertoires partagés et le current vers les relaease
# le redemarrage des serveurs
#---------------------------------------------------------------------------------------------------------------------

lock '3.4.1'

set :application, 'saas'
set :repo_url, "https://github.com/devscrapper/#{fetch(:application)}.git/"
set :github_access_token, '64c0b7864a901bc6a9d7cd851ab5fb431196299e'
set :default, 'master'
set :user, 'eric'
set :pty, true
set :use_sudo, true
set :deploy_to, "/home/#{fetch(:user)}/apps/#{fetch(:application)}"
set :rvm_ruby_version, '2.2.3'
set :server_list, ["backlinks_#{fetch(:application)}",
                   "keywords_#{fetch(:application)}",
                   "links_#{fetch(:application)}",
                   "proxies_#{fetch(:application)}"]


# Default branch is :master
# ask :branch, `git rev-parse --abbrev-ref HEAD`.chomp

# Default deploy_to directory is /var/www/my_app_name
# set :deploy_to, '/var/www/my_app_name'

# Default value for :scm is :git
# set :scm, :git

# Default value for :format is :pretty
# set :format, :pretty

# Default value for :log_level is :debug
set :log_level, :debug

# Default value for :pty is false
#set :pty, true

# Default value for :linked_files is []
set :linked_files, fetch(:linked_files, [])

# Default value for linked_dirs is []
set :linked_dirs, fetch(:linked_dirs, []).push('log', 'tmp', 'archive')

# Default value for default_env is {}
set :default_env, {path: "/opt/ruby/bin:$PATH"}

# Default value for keep_releases is 5
set :keep_releases, 3


#before 'deploy:check:linked_files', 'config:push'

# before 'deploy:starting', 'github:deployment:create'
# after  'deploy:starting', 'github:deployment:pending'
# after  'deploy:finished', 'github:deployment:success'
# after  'deploy:failed',   'github:deployment:failure'


#----------------------------------------------------------------------------------------------------------------------
# task list : machine
#----------------------------------------------------------------------------------------------------------------------
namespace :machine do
  task :reboot
  on roles(:app) do
    within release_path do
      run "#{sudo} reboot"
    end
  end
end


#----------------------------------------------------------------------------------------------------------------------
# task list : log
#----------------------------------------------------------------------------------------------------------------------
namespace :log do
  task :down do
    on roles(:app) do
      begin
        capture("ls #{File.join(current_path, 'log', '*.*')}").split(/\r\n/).each { |log_file|
          get log_file, File.join(File.dirname(__FILE__), '..', 'log', File.basename(log_file))
        }
      rescue Exception => e
        p "dont down log : #{e.message}"
      end
    end
  end
  task :delete do
    on roles(:app) do
      begin
        sudo "rm #{File.join(current_path, 'log', '*.*')}"
      rescue Exception => e
      end
    end
  end


end

#----------------------------------------------------------------------------------------------------------------------
# task list : git push
#----------------------------------------------------------------------------------------------------------------------
namespace :git do
  task :push do
    on roles(:all) do
      run_locally do
        system 'git push origin master'
      end
    end
  end
end
#----------------------------------------------------------------------------------------------------------------------
# task list : deploy
#----------------------------------------------------------------------------------------------------------------------
namespace :deploy do
  task :bundle_install do
    on roles(:app) do
      within release_path do
        execute :bundle, "--gemfile Gemfile --path #{shared_path}/bundle  --binstubs #{shared_path}bin --without [:development]"
      end
    end
  end
  #deploiement des fichier de controle .conf pour automatiser le demarrage au boot
  task :control do
    on roles(:app) do
      within release_path do
        # suppression des fichier de controle pour upstart

        fetch(:server_list).each { |server|
          begin
            sudo " rm --interactive=never -f /etc/init/#{server}.conf"
          rescue Exception => e
            p "KO : suppression du fichier de controle pour upstart #{server} : #{e.message}"
          end
          begin
            # déploiement des fichier de controle pour upstart
            sudo " cp #{File.join(current_path, 'control', "#{server}.conf")} /etc/init"
          rescue Exception => e
            p "KO : deploiement des fichier de controle pour upstart : #{e.message}"
          end
        }
      end
    end
  end

  task :start do
    on roles(:app) do
      fetch(:server_list).each { |server|
        begin
          sudo "initctl start #{server}"
        rescue Exception => e
          p "dont start #{server} : #{e.message}"
        end
      }


    end
  end
  task :stop do
    on roles(:app) do

      fetch(:server_list).each { |server|
        begin
          sudo "initctl stop #{server}"
        rescue Exception => e
          p "dont start #{server} : #{e.message}"
        end
      }

    end
  end
  task :status do
    on roles(:app) do

      fetch(:server_list).each { |server|
        begin
          sudo "initctl status #{server}"
        rescue Exception => e
          p "dont start #{server} : #{e.message}"
        end
      }

    end
  end
  task :restart do
    on roles(:app) do
      within release_path do
        stop
        start
      end
    end
  end
  task :environment do
    on roles(:app) do
      within release_path do

        execute("echo 'staging: test' >  #{File.join(current_path, 'parameter', 'environment.yml')}")
      end
    end
  end

end


before 'deploy:check:linked_files', 'config:push'
before 'deploy:updating', "deploy:stop"
before 'deploy:updating', "git:push"
after "deploy:stop", "log:delete"

# TO update gem  : uncomment under line
after 'deploy:updating', 'deploy:bundle_install'
after 'deploy:updating', "deploy:control"
after 'deploy:updating', "deploy:environment"
after "deploy:control", "deploy:start"
after "deploy:start", "deploy:status"