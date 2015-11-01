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
         :logger


    def initialize(webdriver_with_gui, logger)
      @logger = logger
      @webdriver_with_gui = webdriver_with_gui
      @logger.an_event.debug "webscrapers factory create"
    end


    # retourne un objet webdriver démarré ou
    # retourne une exception si plus aucun webdriver de disponible dans la factory
    # retourn une exception si pb techique lors du lancement

    def book(geolocation=nil, webdriver_with_gui=nil)
      # surcharge lors de la réservation de l'utilisation ou pas de gui
      # par defaut utilise le paramétrage fourni à webscraper_factory issu de scrape_server

      @webdriver_with_gui = webdriver_with_gui unless webdriver_with_gui.nil?
      webscrapper = nil
      begin

        if @webdriver_with_gui
          webscrapper = WebscraperGui.new(geolocation)

        else
          webscrapper = WebscraperHeadless.build(geolocation)

        end

      rescue Exception => e
        @logger.an_event.error e.message
        raise Error.new(SCRAPER_NOT_BOOK, :error => e)

      else
        webscrapper.start
        @logger.an_event.debug "webscraper booked #{webscrapper.to_s}"
        webscrapper # ne pas deplacer dnas ensure sinon retourn true  mais pas l'objet

      ensure

      end
    end

    def free(webscraper)

      begin
        raise Error.new(ARGUMENT_UNDEFINE, :values => {:variable => "webscraper"}) if webscraper.nil?

        webscraper.stop

      rescue Error => e
        @logger.an_event.error e.message
        raise Error.new(SCRAPER_NOT_FREE, :error => e)

      else

        @logger.an_event.debug "webscraper freed #{webscraper.to_s}"

      ensure

      end
    end


    private


  end
end