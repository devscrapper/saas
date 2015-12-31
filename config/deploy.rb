#---------------------------------------------------------------------------------------------------------------------
# deploy.rb
# il est utilisé pour :
# maj les paquets system ubuntu
# installé les outils de compilation (build_essential, libtool, libyaml)
# installé rvm
# installé ruby
# installé les gem de l'application dans un gemset
# déployé l'application
# arrter uo démarrer l'application
# redemarrer la machine
# ---------------------------------------------------------------------------------------------------------------------
# liste de taches de déploiement
# cap rvm:install_rvm :
#     before : maj les paquets du system ubuntu
#     installe rvm
# cap rvm:install_ruby :
#     install ruby avec autolibs=:enable (3) ce qui permet d'installer automatiquement les composants (build_essential, libtool, libyaml) pour ruby
#      remarque : correction du fichier D:\Ruby193\lib\ruby\gems\1.9.1\gems\rvm-capistrano-1.5.3\lib\rvm\capistrano\install_ruby.rb pour prendre en compte
#     le flag :enable
#     remplacement de   : autolibs_flag = "1" unless autolibs_flag_no_requirements
#                   par : autolibs_flag = "1" if autolibs_flag_no_requirements
#     after : create alias default ruby
# cap deploy:setup :
#     before : creation gemset,
#     before : install gem  à partir du Gemfile local
#     creation des repertoire partagé (shared_children)
# cap deploy:update :
#     déploie l'application dans une nouvelle release
#     after : en mettant à jour les liens symbolic,
#     after : paramtrage de fichier de environement.yml
#     after : parametrage du serveur ftp
# cap deploy:start/stop/restart : démarrer stop ou redemmarre tous les serveurs de l'application
# cap deploy:all_param : upload tous les fichiers de parametrage du repertoire ./parameter vers la machine cible
# cap deploy:repo : upload les repository backlink et keyword vers le répertoire /tmp de la machine cible
# cap deploy:gem_list : installe les gem sur la machine cible en fonction du Gemfile local
#----------------------------------------------------------------------------------------------------------------------
# liste taches administrative
# cap machine:reboot : redemarre le serveur physique
# cap log:down : telecharge toutes les log sur la machine locale
# cap log:delete : supprime toutes les log du repertoire /log
#----------------------------------------------------------------------------------------------------------------------
# liste taches de test
# cap test:scraper
# cap test:calender
#----------------------------------------------------------------------------------------------------------------------
# ordre de lancement des commandes deploy : first deploy
# 1 cap rvm:install_rvm
# 2 cap rvm:install_ruby
# 2 cap deploy:setup
# 3 cap deploy:update
# 4 cap machine:reboot
#----------------------------------------------------------------------------------------------------------------------
# ordre de lancement des commandes deploy : next deploy
# 1 cap deploy:gem_list  #installe les nouveaux gem si besoin
# 2 cap deploy:update    # deploie les sources
# 3 cap deploy:restart   # demarre les serveurs
#----------------------------------------------------------------------------------------------------------------------
#on n'utilise pas bundle pour déployer les gem=> on utilise les gem installés sous ruby : les gems system dans un gemset
#----------------------------------------------------------------------------------------------------------------------


require 'pathname'

#----------------------------------------------------------------------------------------------------------------------
# proprietes de l'application
#----------------------------------------------------------------------------------------------------------------------

set :application, "saas" # nom application (github)
set :shared_children, ["archive",
                       "log",
                       "tmp"]
set :server_list, ["keywords_#{application}",
                   "referrals_#{application}",
                   "links_#{application}"]


#----------------------------------------------------------------------------------------------------------------------
# param rvm
#----------------------------------------------------------------------------------------------------------------------
require "rvm/capistrano" #  permet aussi d'installer rvm et ruby
require "rvm/capistrano/alias_and_wrapp"
require "rvm/capistrano/gem_install_uninstall"
set :rvm_ruby_string, '2.2.3' # defini la version de ruby a installer
set :rvm_type, :system #RVM installed in /usr/local, multiuser installation
set :rvm_autolibs_flag, :enable #permet d'installer automatiquement les composants (build_essential, libtool, libyaml) pour ruby
set :bundle_dir, '' # on n'utilise pas bundle pour instaler les gem
set :bundle_flags, '--system --quiet' # on n'utilise pas bundle pour instaler les gem
set :rvm_install_with_sudo, true


#----------------------------------------------------------------------------------------------------------------------
# param extraction git
#----------------------------------------------------------------------------------------------------------------------

ENV["path"] += ";d:\\\personnel\\portableGit\\bin" # acces au git local à la machine qui execute ce script
set :repository, "file://d:/personnel/referentiel/src/#{application}/.git"
set :scm, "git"
set :copy_dir, "d:\\temp" # reperoitr temporaire de d'extracion des fichiers du git pour les zipper
set :branch, "master" # version à déployer

#----------------------------------------------------------------------------------------------------------------------
# param déploiement vers server cible
#----------------------------------------------------------------------------------------------------------------------

set :keep_releases, 3 # nombre de version conservées
set :server_name, "192.168.1.88" # adresse du server de destination

set :deploy_to, "/usr/local/rvm/wrappers/#{application}" # repertoire de deploiement de l'application
#set :server_name, "olgadays.synology.me" #adresse du server de destination hors reseau local
set :deploy_via, :copy # using a local scm repository which cannot be accessed from the remote machine.
set :user, "eric"
set :password, "Brembo01"
default_run_options[:pty] = true
set :use_sudo, true
set :staging, "test"
role :app, server_name


before 'rvm:install_rvm', 'avant:install_rvm'
before 'rvm:install_ruby', 'rvm:create_gemset'
after 'rvm:install_ruby', 'apres:install_ruby', 'apres:install_imagemagick', 'apres:install_firefox', 'apres:install_xfvb'
before 'deploy:setup', 'rvm:create_alias', 'rvm:create_wrappers', 'deploy:gem_list'
after "deploy:update", "apres:update", "deploy:start", "deploy:status"
before "deploy:update", "deploy:stop", "log:delete"


#----------------------------------------------------------------------------------------------------------------------
# task list : log
#----------------------------------------------------------------------------------------------------------------------
namespace :log do

  task :down, :roles => :app do
    capture("ls #{File.join(current_path, 'log', '*.*')}").split(/\r\n/).each { |log_file|
      get log_file, File.join(File.dirname(__FILE__), '..', 'log', File.basename(log_file))
    }
  end

  task :delete, :roles => :app do
    run "rm #{File.join(current_path, 'log', '*')}"
  end

end

#----------------------------------------------------------------------------------------------------------------------
# task list : machine
#----------------------------------------------------------------------------------------------------------------------
namespace :machine do
  task :reboot, :roles => :app do
    run "#{sudo} reboot"
  end
end

#----------------------------------------------------------------------------------------------------------------------
# task list : deploy
#----------------------------------------------------------------------------------------------------------------------
namespace :deploy do
  task :all_param do
    top.upload(File.join(File.dirname(__FILE__), '..', 'parameter'), File.join(current_path, 'parameter'))
  end

  task :repo do # upload repository bakclinket keywords
    repo_files = File.join(File.dirname(__FILE__), '..', 'tmp', "repository*.txt")
    Dir.glob(repo_files) { |file|
      top.upload(file,
                 File.join(current_path, 'tmp', File.basename(file)))
    }
  end

  task :start, :roles => :app, :except => {:no_release => true} do
    server_list.each { |server|
      begin
        run "#{sudo} initctl start #{server}"
      rescue Exception => e
        p "#{server} not start : #{e.message}"
      end
    }
  end

  task :stop, :roles => :app, :except => {:no_release => true} do
    server_list.each { |server|
      begin
        run "#{sudo} initctl stop #{server}"
      rescue Exception => e
        p "#{server} not stop : #{e.message}"
      end }
  end

  task :status, :roles => :app, :except => {:no_release => true} do
    server_list.each { |server| run "#{sudo} initctl status #{server}" }
  end

  task :restart, :roles => :app, :except => {:no_release => true} do
    stop
    start
  end

  task :first, :roles => :app do
    rvm.install_rvm
    rvm.install_ruby
    deploy.setup
    deploy.update
    machine.reboot
  end

  task :gem_list, :roles => :app do
    #installation des gem dans le gesmset
    gemlist(File.expand_path(File.join("..", "..", "Gemfile"), __FILE__)).each { |parse|
      run_without_rvm("#{path_to_bin_rvm(:with_ruby => rvm_ruby_string_evaluated)} gem query -I #{parse[:name].strip} -v #{parse[:version].strip} ; if [  $? -eq 0 ] ; then #{path_to_bin_rvm(:with_ruby => rvm_ruby_string_evaluated)} gem install #{parse[:name].strip} -v #{parse[:version].strip} -N ; else echo \"gem #{parse[:name].strip} #{parse[:version].strip} already installed\" ; fi")
    }
    run_without_rvm("#{path_to_bin_rvm(:with_ruby => rvm_ruby_string_evaluated)} gem query -i jwt -v 1.0.0 ; if [  $? -eq 0 ] ; then #{path_to_bin_rvm(:with_ruby => rvm_ruby_string_evaluated)} gem uninstall jwt -v 1.0.0 ; else echo \"gem jwt -v 1.0.0 not installed\" ; fi")
  end
end

#----------------------------------------------------------------------------------------------------------------------
# task list : data :
#----------------------------------------------------------------------------------------------------------------------
namespace :data do
  task :clear do
    run "rm #{File.join(current_path, 'archive', '*')} -y"
    run "rm #{File.join(current_path, 'tmp', '*')} -y"


  end
end

#----------------------------------------------------------------------------------------------------------------------
# task list : avant :
#----------------------------------------------------------------------------------------------------------------------
namespace :avant do
  task :install_rvm do
    run_without_rvm ("#{sudo} apt update")
    run_without_rvm ("#{sudo} apt -y full-upgrade")
  end
end
#----------------------------------------------------------------------------------------------------------------------
# task list : apres :
#----------------------------------------------------------------------------------------------------------------------
namespace :apres do
  task :install_ruby do
    run_rvm ("alias create default #{rvm_ruby_string}")
  end

  # necessité à confirmer pour xvfb fin
  #necessaire pour faire des screenshot pôur xvfb debut
  task :install_imagemagick do
    run "#{sudo} apt-get install imagemagick -y"
  end

  #necessaire pour faire des screenshot pôur xvfb fin
  task :install_firefox do
    run "#{sudo} apt-get install firefox -y"
  end

  task :install_xfvb do
    run "#{sudo} apt-get install xvfb -y"
  end

  task :update do
    # suppression des fichier de controle pour upstart
    server_list.each { |server|
      run "#{sudo} rm --interactive=never -f /etc/init/#{server}.conf"
    }
    # déploiement des fichier de controle pour upstart
    run "#{sudo} cp #{File.join(current_path, 'control', '*')} /etc/init"

    #creation des lien vers les repertoire partagés
    shared_children.each { |dir|
      run "ln -f -s #{File.join(deploy_to, "shared", dir)} #{File.join(current_path, dir)}"
    }

    # definition du type d'environement
    run "echo 'staging: #{staging}' >  #{File.join(current_path, 'parameter', 'environment.yml')}"
  end


end

#----------------------------------------------------------------------------------------------------------------------
# put_sudo
#----------------------------------------------------------------------------------------------------------------------
# permet d'uploader un fichier dans un repertoire pour lequel il faut des droits administrateur ; exemple /etc/init
#----------------------------------------------------------------------------------------------------------------------
def put_sudo(data, to)
  filename = File.basename(to)
  to_directory = File.dirname(to)
  put data, "/tmp/#{filename}"
  run "#{sudo} mv /tmp/#{filename} #{to_directory}"
end

#----------------------------------------------------------------------------------------------------------------------
# gemlist
#----------------------------------------------------------------------------------------------------------------------
# permet de recuperer la liste des gem à partir du Gemfile à installer.
#----------------------------------------------------------------------------------------------------------------------
def gemlist(file)
  gemlist = []
  gemfile = File.open(file)
  catch_gem = true
  gemfile.readlines.each { |line|
    case line
      when /gem (.*)/
        if catch_gem
          gemlist << /gem '(?<name>.*)', '(~> )*(?<version>\d+\.\d+(\.\d+)*)'/.match(line)
        end
      when /.*:development.*/
        catch_gem = false
      when /;*:production.*/
        catch_gem = true
    end
  }
  gemlist
end
















