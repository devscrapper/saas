require 'eventmachine'

require_relative '../error'
require_relative 'webscraper'


module Webscrapers
  #----------------------------------------------------------------------------------------------------------------
  # include class
  #----------------------------------------------------------------------------------------------------------------
  include Errors

  #----------------------------------------------------------------------------------------------------------------
  # Message exception
  #----------------------------------------------------------------------------------------------------------------

  ARGUMENT_UNDEFINE = 1400
  SCRAPER_NOT_BOOK = 1401
  SCRAPER_NOT_FREE = 1402


  class WebscraperFactory
    include Errors


    attr :webdriver_with_gui, #la factory propose des webdriver soit avec gui => firefox, soit headless =>  phantomjs
         # sous linux/unix : le webdriver avec gui s'execute avec xfvb
         :logger,
         :webdrivers_free, # ensemble des webdriver libres
         :webdrivers_busy, # ensemble des webdriver occupés
         :sem # protege l'acces à webdriver_array qui est utilisé dans des thread.


    def initialize(webdriver_with_gui, webdriver_count = 1, geolocation, logger)
      @logger = logger
      @webdriver_with_gui = webdriver_with_gui
      @webdrivers_free = []
      @webdrivers_busy = []
      webdriver_count.times {
        webscrapper = @webdriver_with_gui ?
            WebscraperGui.new(geolocation)
        :
            WebscraperHeadless.build(geolocation)

        @webdrivers_free << webscrapper

        webscrapper.start
      }
      @sem = Mutex.new
      @logger.an_event.debug "webscrapers factory create"

    end


    # retourne un array d'objet webdriver démarré ou
    # retourne une exception si plus aucun webdriver de disponible dans la factory
    # retourn une exception si pb techique lors du lancement

    def book(count = 1, geolocation=nil) #TODO geolocation est requis si book peut demarrer une nouvelle instance de webdriver  EVOL

      webdrivers = nil
      begin


        @sem.synchronize {
          webdrivers = @webdrivers_free.shift(count)
          raise "no webdriver free" if webdrivers.nil?

          @webdrivers_busy += webdrivers
        }

      rescue Exception => e
        @logger.an_event.error e.message
        raise Error.new(SCRAPER_NOT_BOOK, :error => e)

      else
        @logger.an_event.debug "webscraper booked #{webdrivers.to_s}"
        webdrivers # ne pas deplacer dnas ensure sinon retourn true  mais pas l'objet

      ensure

      end
    end

    def delete_all
      @sem.synchronize {
        @webdrivers_free.each{|webdriver| webdriver.stop}
        @webdrivers_busy.each{|webdriver| webdriver.stop}
      }

    end
    def free(webdriver)

      begin
        raise Error.new(ARGUMENT_UNDEFINE, :values => {:variable => "webdriver"}) if webdriver.nil?

        @sem.synchronize {
          @webdrivers_free << webdriver
          @webdrivers_busy.delete(webdriver) { "webdriver not found" }
        }

      rescue Error => e
        @logger.an_event.error e.message
        raise Error.new(SCRAPER_NOT_FREE, :error => e)

      else

        @logger.an_event.debug "webscraper freed #{webdriver.to_s}"

      ensure

      end
    end


  end
end