#!/usr/bin/env ruby -w
# encoding: UTF-8
require "logging"

module Logging
  # la stratégie de logging est conditionnée par trois critères :
  # staging : development, test, production
  # debugging : true, false
  # niveau du programme : Object (main programme), class (not Object)

  #tableau des appenders
  #--------------------------------------------------------------------------------------
  #         |           DEBUGGING                 |         NOT DEBUGGING               |
  #--------------------------------------------------------------------------------------
  #         |    PROD/TEST     |      DEV         |   PROD/TEST      |      DEV         |
  #--------------------------------------------------------------------------------------
  #         | OBJECT | CLASS   | OBJECT | CLASS   | OBJECT | CLASS   | OBJECT | CLASS   |
  #--------------------------------------------------------------------------------------
  #> :fatal | email  |additive*| email  |additive*| email  |additive*| email  |additive*|
  #--------------------------------------------------------------------------------------
  #> :info  | syslog |additive*| stdout |additive*| syslog,|additive*| stdout,|additive*|
  #         |        |         |        |         |rollfile|         |rollfile|         |
  #--------------------------------------------------------------------------------------
  #> :debug |debfile, |debfile,|debfile,|debfile, |                                      |
  #         |ymlfile  |ymlfile |ymlfile |ymlfile  |
  #--------------------------------------------------------------------------------------
  #         |param(1)|param(2) |param(3)|param(2) |param(4)|param(5) |param(6)|param(5) |
  #--------------------------------------------------------------------------------------
  # *additive = true : un composant non Object doit remonter ses event de log vers son parent
  #--------------------------------------------------------------------------------------

  STAGING_DEV = "development"
  STAGING_TEST = "test"
  STAGING_PROD = "production"

  class Log
    DIR_LOG = File.dirname(__FILE__) + "/../log"
    attr_reader :logger
    attr :staging,
         :debugging,
         :main,
         :id_file,
         :class_name
    alias :a_log :logger
    alias :an_event :logger

    public


    def initialize(obj, opts = {})
      if Logging::initialized?
        @logger = Logging::Logger[obj]
        #Logging::show_configuration
      else
        @staging = opts.fetch(:staging, STAGING_PROD)
        @debugging = opts.fetch(:debugging, false)
        @class_name = obj.class.name.gsub("::", "_")
        @main = @class_name == Object.name
        param_1(opts) if @debugging and [STAGING_TEST, STAGING_PROD].include?(@staging) and @main
        param_4(opts) if !@debugging and [STAGING_TEST, STAGING_PROD].include?(@staging) and @main

        param_2(obj) if @debugging and !@main
        param_5(obj) if !@debugging and !@main

        param_3(opts) if @debugging and [STAGING_DEV].include?(@staging) and @main
        param_6(opts) if !@debugging and [STAGING_DEV].include?(@staging) and @main
        Logging::show_configuration
      end
      @logger.debug "logging is available"
    end


    def ndc(args)
      args.each { |arg| Logging.ndc.push arg }
    end


    def email()
      #TODO valider le parametrage de l'appender mail

#      port 25 : sans authentificationnote 2, connexion non sécurisée
#      port 465 : authentification permettant l'envoi d'e-mails depuis n'importe quel point d'accès, connexion sécurisée
#      port 587 : authentification permettant l'envoi d'e-mails depuis n'importe quel point d'accès, connexion non sécurisée
#      Si une méthode de sécurité vous est proposée, choisissez SSL / TLS port 465 (ou MD5 port 587).
#      L'authentification SMTP est strictement inutile si la connexion utilisée lors de l'envoi d'eMails appartient au réseau Free.
#      Cette option est clairement destinée à l'envoi d'eMails depuis une connexion appartenant à un opérateur différent.
      Logging::appenders.email('email',
                               :from => "error@log.com",
                               :to => "olinouane@gmail.com",
                               :subject => "Application Error []",
                               :address => "smtp.gmail.com",
                               :port => 587,
                               :domain => "google.com",
                               :user_name => "olinouane",
                               :password => "Brembo01",
                               :authentication => :cram_md5,
                               :enable_starttls_auto => true,
                               :auto_flushing => 200, # send an email after 200 messages have been buffered
                               :flush_period => 60, # send an email after one minute
                               :level => :fatal # only process log events that are "error" or "fatal"
      )
    end

    def syslog()
      Logging::Appenders.syslog(@class_name)
    end

    def rollfile()
      opt = {:truncate => true, :size => 5000000, :keep => 10, :roll_by => :number} if @debugging
      opt = {:age => :daily, :keep => 7, :roll_by => :date} unless  @debugging
      Logging::Appenders.rolling_file(File.join(DIR_LOG, "#{@id_file}.log"), opt)
    end


    def stdout()
      Logging::color_scheme('bright',
                            :levels => {
                                :info => :green,
                                :warn => :yellow,
                                :error => :red,
                                :fatal => [:white, :on_red]
                            },
                            :date => :blue,
                            :logger => :cyan,
                            :message => :black
      )

      Logging::Appenders.stdout(:level => :info, :layout => Logging.layouts.pattern(
          :pattern => '[%d] %-5l %c: %m\n',
          :color_scheme => 'bright'
      ))
    end

    def debfile
      Logging::Appenders.rolling_file(File.join(DIR_LOG, "#{@id_file}.deb"),
                                      {:age => :daily,
                                       :keep => 7,
                                       :roll_by => :date,
                                       :layout => Logging.layouts.pattern(:pattern => '[%d] %-5l %-16c %-32M %-5L %x{,} :  %m %F\n')})


    end

    def ymlfile
      Logging::Appenders.rolling_file(File.join(DIR_LOG, "#{@id_file}.yml"),
                                      {:age => :daily,
                                       :keep => 7,
                                       :roll_by => :date,
                                       :layout => Logging.layouts.yaml})

    end

    def param_1(opts)
      @id_file = opts.fetch(:id_file, "root")
      @logger = Logging.logger["root"]
      @logger.level = :debug
      @logger.add_appenders(email)
      @logger.add_appenders(syslog)  if HAVE_SYSLOG
      @logger.add_appenders(debfile)
      @logger.add_appenders(ymlfile)
    end

    def param_2(obj)
      @id_file = @class_name.downcase
      @logger = Logging.logger[obj]
      @logger.additive = true
      @logger.level = :debug
      @logger.add_appenders(debfile)
      @logger.add_appenders(ymlfile)
    end

    def param_3(opts)
      @id_file = opts.fetch(:id_file, "root")
      @logger = Logging.logger["root"]
      @logger.level = :debug
      @logger.add_appenders(email)
      @logger.add_appenders(stdout)
      @logger.add_appenders(debfile)
      @logger.add_appenders(ymlfile)
    end

    def param_4(opts)
      @id_file = opts.fetch(:id_file, "root")
      @logger = Logging.logger["root"]
      @logger.level = :info
      @logger.add_appenders(email)
      @logger.add_appenders(syslog)  if HAVE_SYSLOG
      @logger.add_appenders(rollfile)
    end

    def param_5(obj)
      @logger = Logging.logger[obj]
      @logger.additive = true
      @logger.level = :info
    end

    def param_6(opts)
      @id_file = opts.fetch(:id_file, "root")
      @logger = Logging.logger["root"]
      @logger.level = :info
      @logger.add_appenders(email)
      @logger.add_appenders(stdout)
      @logger.add_appenders(rollfile)
    end
  end
end