#!/usr/bin/env ruby -w
# encoding: UTF-8
require 'yaml'
require 'trollop'
require 'rufus-scheduler'
require_relative '../lib/logging'
require_relative '../lib/parameter'
require_relative '../lib/geolocation/geolocation_factory'
require_relative '../lib/webscraper/webscraper_factory'
require_relative '../lib/supervisor'
require_relative '../model/keywords_connection'
=begin
Bot scrape traffic source (referral, organic)
Bot scrape hourly daily distribution
Bot scrape behaviour
Bot scrape platforme plugin and resolution
Bot scrape website
Bot evaluate organic and referral scraped


Usage:
       scraper_server [options]
where [options] are:
                           --proxy-type, -p <s>:   Type of geolocation proxy
                                                   use (default : none |
                                                   factory | http) (default:
                                                   none)
                             --proxy-ip, -r <s>:   @ip of geolocation proxy
                           --proxy-port, -o <i>:   Port of geolocation proxy
                           --proxy-user, -x <s>:   Identified user of
                                                   geolocation proxy
                            --proxy-pwd, -y <s>:   Authentified pwd of
                                                   geolocation proxy
                       --webdriver-with-gui, -w:   Webdriver with gui(true) or
                                                   headless(default : false)
  --[[:depends, [:proxy-user, :proxy-pwd]]], -[:
                                  --version, -v:   Print version and exit
                                     --help, -h:   Show this message
=end
#--------------------------------------------------------------------------------------------------------------------
# INIT
#--------------------------------------------------------------------------------------------------------------------

TMP = File.expand_path(File.join("..", "..", "tmp"), __FILE__)


opts = Trollop::options do
  version "keywords_saas 0.1 (c) 2015 Dave Scrapper"
  banner <<-EOS
Saas scrape organic keywords from semrush

Usage:
       keywords_saas [options]

where [options] are:
  EOS
  opt :proxy_type, "Type of geolocation proxy use (default : none | factory | http)", :type => :string, :default => "none"
  opt :proxy_ip, "@ip of geolocation proxy", :type => :string
  opt :proxy_port, "Port of geolocation proxy", :type => :integer
  opt :proxy_user, "Identified user of geolocation proxy", :type => :string
  opt :proxy_pwd, "Authentified pwd of geolocation proxy", :type => :string
  opt :webdriver_with_gui, "Webdriver with gui(true) or headless(default : false)", :type => :boolean, :default => false
  opt depends(:proxy_user, :proxy_pwd)
end

Trollop::die :proxy_type, "is not in (none|factory|http)" if !["none", "factory", "http"].include?(opts[:proxy_type])
Trollop::die :proxy_ip, "is require with proxy" if ["http"].include?(opts[:proxy_type]) and opts[:proxy_ip].nil?
Trollop::die :proxy_port, "is require with proxy" if ["http"].include?(opts[:proxy_type]) and opts[:proxy_port].nil?


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
  delay_periodic_load_geolocations = parameters.delay_periodic_load_geolocations
  listening_port = parameters.listening_port
  periodicity_supervision = parameters.periodicity_supervision
end


logger = Logging::Log.new(self, :staging => $staging, :id_file => File.basename(__FILE__, ".rb"), :debugging => $debugging)

logger.a_log.info "parameters of calendar server :"
logger.a_log.info "listening port : #{listening_port}"
logger.a_log.info "geolocation : #{opts[:proxy_type]}"
logger.a_log.info "proxy ip:port : #{opts[:proxy_ip]}:#{opts[:proxy_port]}" if opts[:proxy_type] == "http"
logger.a_log.info "proxy user/pwd : #{opts[:proxy_user]}:#{opts[:proxy_pwd]}" unless opts[:proxy_user].nil?
logger.a_log.info "webdriver with gui : #{opts[:webdriver_with_gui]}"
logger.a_log.info "delay_periodic_load_geolocations (minute) : #{delay_periodic_load_geolocations}"
logger.a_log.info "periodicity supervision : #{periodicity_supervision}"
logger.a_log.info "debugging : #{$debugging}"
logger.a_log.info "staging : #{$staging}"

#--------------------------------------------------------------------------------------------------------------------
# MAIN
#--------------------------------------------------------------------------------------------------------------------


webscraper_factory = Webscrapers::WebscraperFactory.new(opts[:webdriver_with_gui], logger)
begin
  EventMachine.run {
    Signal.trap("INT") { EventMachine.stop }
    Signal.trap("TERM") { EventMachine.stop }


    logger.a_log.info "scraper server is running"
    Supervisor.send_online(File.basename(__FILE__, '.rb'))

    case opts[:proxy_type]
      when "none"

        logger.a_log.info "none geolocation"
        geolocation = nil

      when "factory"

        logger.a_log.info "factory geolocation"
        geolocation_factory = Geolocations::GeolocationFactory.new(delay_periodic_load_geolocations * 60, logger)
        geolocation = geolocation_factory.get

      when "http"

        logger.a_log.info "default geolocation : #{opts[:proxy_ip]}:#{opts[:proxy_port]}"
        geo_flow = Flow.new(TMP, "geolocations", :none, $staging, Date.today)
        geo_flow.write(["fr", opts[:proxy_type], opts[:proxy_ip], opts[:proxy_port], opts[:proxy_user], opts[:proxy_pwd]].join(Geolocations::Geolocation::SEPARATOR))
        geo_flow.close
        geolocation_factory = Geolocations::GeolocationFactory.new(delay_periodic_load_geolocations * 60, logger)
        geolocation = geolocation_factory.get

    end
    # supervision
    Rufus::Scheduler.start_new.every periodicity_supervision do
      Supervisor.send_online(File.basename(__FILE__, '.rb'))
    end
    EventMachine.start_server "0.0.0.0", listening_port, KeywordsConnection, geolocation, webscraper_factory, logger


  }
rescue Exception => e
  logger.a_log.fatal e
  logger.a_log.warn "keywords saas restart"
  retry
  logger.a_log.fatal "keywords saas stops abruptly : #{e.message}"

end
logger.a_log.info "keywords saas sopped"



















