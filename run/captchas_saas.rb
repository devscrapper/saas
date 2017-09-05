#!/usr/bin/env ruby -w
# encoding: UTF-8
require 'yaml'
require 'trollop'
require 'rufus-scheduler'
require 'open-uri'
require_relative '../lib/logging'
require_relative '../lib/parameter'
require_relative '../model/captchas_connection'
require_relative '../lib/supervisor'

#--------------------------------------------------------------------------------------------------------------------
# INIT
#--------------------------------------------------------------------------------------------------------------------

TMP = File.expand_path(File.join("..", "..", "tmp"), __FILE__)


opts = Trollop::options do
  version "captchas_saas 0.1 (c) 2016 Dave Scrapper"
  banner <<-EOS
Saas get sring value of captcha

Usage:
       captchas_saas

where [options] are:
  EOS
end

#--------------------------------------------------------------------------------------------------------------------
# LOAD PARAMETER
#--------------------------------------------------------------------------------------------------------------------

begin
  parameters = Parameter.new(__FILE__)
rescue Exception => e
  $stderr << e.message << "\n"
else
  $staging = parameters.environment
  $debugging = parameters.debugging
  listening_port = parameters.listening_port
  periodicity_supervision = parameters.periodicity_supervision
end

TMP = Pathname(File.join(File.dirname(__FILE__), '..', 'tmp')).realpath

logger = Logging::Log.new(self, :staging => $staging, :id_file => File.basename(__FILE__, ".rb"), :debugging => $debugging)

logger.a_log.info "parameters of calendar server :"
logger.a_log.info "listening port : #{listening_port}"
logger.a_log.info "periodicity supervision : #{periodicity_supervision}"
logger.a_log.info "debugging : #{$debugging}"
logger.a_log.info "staging : #{$staging}"

#--------------------------------------------------------------------------------------------------------------------
# MAIN
#--------------------------------------------------------------------------------------------------------------------

begin
  EventMachine.run {
    Signal.trap("INT") { EventMachine.stop }
    Signal.trap("TERM") { EventMachine.stop }


    logger.a_log.info "saas is running"
    Supervisor.send_online(File.basename(__FILE__, '.rb'))

    Rufus::Scheduler.start_new.every periodicity_supervision do
      Supervisor.send_online(File.basename(__FILE__, '.rb'))
    end

    EventMachine.start_server "0.0.0.0", listening_port, CaptchasConnection, logger


  }

rescue Exception => e
  logger.a_log.fatal e
  logger.a_log.warn "captchas saas restart"
  retry
  logger.a_log.fatal "captchas saas stops abruptly : #{e.message}"

end
logger.a_log.info "captchas saas stopped"
























