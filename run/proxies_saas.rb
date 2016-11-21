#!/usr/bin/env ruby -w
# encoding: UTF-8
require 'yaml'
require 'trollop'
require 'rufus-scheduler'
require 'open-uri'
require_relative '../lib/logging'
require_relative '../lib/parameter'
require_relative '../lib/geolocation/geolocation_factory'
require_relative '../lib/supervisor'
require_relative '../model/proxies_connection'
=begin
saas get proxy list

Usage:
       scraper_server [options]
where [options] are:

  --[[:depends, [:proxy-user, :proxy-pwd]]], -[:
                                  --version, -v:   Print version and exit
                                     --help, -h:   Show this message
=end
#--------------------------------------------------------------------------------------------------------------------
# INIT
#--------------------------------------------------------------------------------------------------------------------

TMP = File.expand_path(File.join("..", "..", "tmp"), __FILE__)


opts = Trollop::options do
  version "proxies_saas 0.1 (c) 2016 Dave Scrapper"
  banner <<-EOS
Saas get proxy list

Usage:
       proxies_saas

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
  delay_periodic_get_proxy_list = parameters.delay_periodic_get_proxy_list
  listening_port = parameters.listening_port
  periodicity_supervision = parameters.periodicity_supervision
  proxy_list_url = parameters.proxy_list_url
end

TMP = Pathname(File.join(File.dirname(__FILE__), '..', 'tmp')).realpath

logger = Logging::Log.new(self, :staging => $staging, :id_file => File.basename(__FILE__, ".rb"), :debugging => $debugging)

logger.a_log.info "parameters of calendar server :"
logger.a_log.info "listening port : #{listening_port}"
logger.a_log.info "delay_periodic_get_proxy_list (minute) : #{delay_periodic_get_proxy_list}"
logger.a_log.info "periodicity supervision : #{periodicity_supervision}"
logger.a_log.info "proxy list url : #{proxy_list_url}"
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
    proxy_list = File.open(File.join(TMP,"proxy_list"), "w+:bom|utf-8")
    proxy_list.write(open(proxy_list_url).read)
    proxy_list.close
    EM.add_periodic_timer(delay_periodic_get_proxy_list * 60 * 60 * 24) do
      proxy_list = File.open(File.join(TMP,"proxy_list"), "w+:bom|utf-8")
      proxy_list.write(open(proxy_list_url).read)
      proxy_list.close
    end

    EventMachine.start_server "0.0.0.0", listening_port, ProxiesConnection, logger


  }

rescue Exception => e
  logger.a_log.fatal e.message
  logger.a_log.warn "proxies saas restart"
  #retry
  logger.a_log.fatal "proxies saas stops abruptly : #{e.message}"

end
logger.a_log.info "proxies saas stopped"
























